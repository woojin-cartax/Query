#!/usr/bin/env python3
"""
MySQL 원천 → parquet → GCS 적재기

  SQL 을 복제하지 않는다. 같은 폴더의 00_mysql_extract.sql 과 02_raw_table.sql 을
  읽어서 쓴다. 복제본은 동기화되지 않는다 — 한쪽만 고치면 조용히 어긋난다.
    00_mysql_extract.sql  무엇을 뽑을 것인가 (SELECT 문)
    02_raw_table.sql      각 컬럼의 타입 (parquet 스키마를 여기서 만든다)

  이 스크립트가 손으로 하면 틀리는 세 가지를 처리한다.
    1. :from / :to 는 MySQL 문법이 아니다. 실제 값으로 바꾼다
    2. MySQL 의 (enabled='X') 는 0/1 정수다. BigQuery BOOL 로 넣으려면
       parquet 단계에서 bool 로 캐스팅해야 한다. 안 하면 적재가 깨진다
    3. drivingLog 2,500만 행을 한 번에 읽으면 메모리가 터진다.
       기본키 기준으로 끊어 읽는다 (OFFSET 은 뒤로 갈수록 느려져 쓰지 않는다)

사용
  # 어제치 증분 (전 테이블)
  python3 extract.py

  # 특정 테이블만, 기간 지정
  python3 extract.py --tables payment,paySchedule --from 2026-09-01 --to 2026-09-12

  # 최초 전량 — 운행은 연도별로 나눠서
  python3 extract.py --tables drivingLog --full --year 2024

  # 실제로 접속하지 않고 만들어질 SQL 만 확인
  python3 extract.py --tables payment --dry-run

접속 정보는 환경변수로 받는다. 코드에 적지 않는다.
  MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD MYSQL_DB
  GCS_BUCKET   (기본 cartax-biz_cartax_statistics)
"""
import argparse, io, os, re, sys, datetime, pathlib

HERE = pathlib.Path(__file__).resolve().parent
SQL_DIR = HERE.parent

# MySQL 테이블 → GCS 폴더. 02_raw_table.sql 의 raw_<이름> 과 같아야 한다
TABLE_MAP = {
    'payment': 'payment',
    'paySchedule': 'pay_schedule',
    'companyPayState': 'company_pay_state',
    'companyPayStateHistory': 'company_pay_state_history',
    'freeExperienceHistory': 'trial_history',
    'company': 'company',
    'drivingLog': 'trip',
    'deleteDrivingLog': 'trip_deleted',
    'loginBrowserHistory': 'login_admin',
    'userLoginHistory': 'login_app',
    'user': 'user',
    'department': 'department',
    'purpose': 'purpose',
    'car': 'vehicle',        # 3순위. 기본 실행 대상이 아니다
}
DEFAULT_TABLES = [t for t in TABLE_MAP if t != 'car']

# 행이 많아 끊어 읽어야 하는 것들. 값은 한 번에 읽을 행 수
CHUNKED = {'drivingLog': 200_000, 'deleteDrivingLog': 200_000,
           'userLoginHistory': 200_000, 'loginBrowserHistory': 200_000}


def parse_selects(path):
    """00_mysql_extract.sql 에서 테이블별 SELECT 문을 뽑는다."""
    text = io.open(path, encoding='utf-8').read()
    out = {}
    for block in re.split(r'\nSELECT\n', text)[1:]:
        m = re.search(r'\nFROM `?(\w+)`?\nWHERE (\w+) >= :from AND \2 < :to;', block)
        if not m:
            continue
        table, inc_col = m.group(1), m.group(2)
        cols = block[:m.start()].rstrip().rstrip(',')
        out[table] = {
            'cols': cols,                       # SELECT 뒤 컬럼 목록
            'from': 'FROM `%s`' % table,        # FROM 절은 우리가 다시 만든다
            'inc_col': inc_col,
        }
    return out


def parse_schema(path):
    """02_raw_table.sql 에서 raw 테이블별 (컬럼, 타입) 목록을 뽑는다."""
    text = io.open(path, encoding='utf-8').read()
    out = {}
    pat = r'CREATE OR REPLACE TABLE `[^`]*\.raw_(\w+)`\s*\((.*?)\n\)\s*\n(?:PARTITION|CLUSTER|OPTIONS)'
    for m in re.finditer(pat, text, re.S):
        cols = []
        for line in m.group(2).split('\n'):
            line = line.split('--')[0].strip().rstrip(',')
            mm = re.match(r'^(\w+)\s+(INT64|STRING|DATE|DATETIME|TIMESTAMP|BOOL|FLOAT64|NUMERIC)', line)
            if mm and mm.group(1) != 'loaded_at':
                cols.append((mm.group(1), mm.group(2)))
        out[m.group(1)] = cols
    return out


def arrow_schema(cols):
    import pyarrow as pa
    t = {'INT64': pa.int64(), 'STRING': pa.string(), 'DATE': pa.date32(),
         'DATETIME': pa.timestamp('us'), 'TIMESTAMP': pa.timestamp('us', tz='UTC'),
         'BOOL': pa.bool_(), 'FLOAT64': pa.float64(),
         'NUMERIC': pa.decimal128(38, 9)}
    return pa.schema([pa.field(n, t[ty]) for n, ty in cols])


def base_where(sel, args, table):
    """기간 조건. --full 이면 비거나 연도 조건만 남는다."""
    if args.full:
        if args.year and table in ('drivingLog', 'deleteDrivingLog'):
            # 운행은 운행일 기준으로 연도를 자른다. 수정 시각이 아니다
            return ["startDate >= '%d-01-01' AND startDate < '%d-01-01'"
                    % (args.year, args.year + 1)]
        return []
    return ["%s >= '%s' AND %s < '%s'"
            % (sel['inc_col'], args.date_from, sel['inc_col'], args.date_to)]


def compose(sel, where, chunk, last_seq):
    """SELECT ... FROM ... WHERE ... [ORDER BY seq LIMIT n] 을 만든다.

    끊어 읽을 때는 seq 를 커서로 하나 더 뽑는다. OFFSET 은 뒤로 갈수록
    느려지므로 쓰지 않는다 — 기본키 기준으로 앞으로만 나아간다.
    커서 컬럼은 parquet 에 넣지 않고 읽은 뒤 떼어낸다."""
    cols = sel['cols']
    if chunk:
        cols += ',\n    seq AS __cursor'
        where = list(where) + ['seq > %d' % last_seq]
    sql = 'SELECT\n' + cols + '\n' + sel['from']
    if where:
        sql += '\nWHERE ' + '\n  AND '.join(where)
    if chunk:
        sql += '\nORDER BY seq LIMIT %d' % chunk
    return sql


def run_table(table, sel, cols, args, conn, bucket):
    import pyarrow as pa, pyarrow.parquet as pq

    schema = arrow_schema(cols)
    bool_idx = [i for i, (_, ty) in enumerate(cols) if ty == 'BOOL']
    names = [n for n, _ in cols]
    where = base_where(sel, args, table)
    chunk = CHUNKED.get(table)
    folder = TABLE_MAP[table]
    dest_dir = '%s/dt=%s' % (folder, args.dt)

    if args.dry_run:
        print('─' * 78)
        print('▌%s → gs://%s/%s' % (table, args.bucket, dest_dir))
        print('  컬럼 %d개, 그중 BOOL %d개를 0/1 에서 캐스팅%s'
              % (len(cols), len(bool_idx),
                 ' · %d행씩 끊어 읽음' % chunk if chunk else ''))
        print(compose(sel, where, chunk, 0) + ';')
        return 0

    total, part, last_seq = 0, 0, 0
    while True:
        sql = compose(sel, where, chunk, last_seq)

        cur = conn.cursor()
        cur.execute(sql)
        rows = cur.fetchall()
        cur.close()
        if not rows:
            break

        if chunk:
            last_seq = rows[-1][-1]
            rows = [r[:-1] for r in rows]

        # MySQL 의 0/1 을 bool 로 바꾼다. 이걸 빼면 BigQuery 적재가 타입에서 깨진다
        data = {}
        for i, name in enumerate(names):
            col = [r[i] for r in rows]
            if i in bool_idx:
                col = [None if v is None else bool(v) for v in col]
            data[name] = col

        tbl = pa.Table.from_pydict(data, schema=schema)
        buf = io.BytesIO()
        pq.write_table(tbl, buf, compression='snappy')
        buf.seek(0)
        blob = bucket.blob('%s/part-%05d.parquet' % (dest_dir, part))
        blob.upload_from_file(buf, content_type='application/octet-stream')

        total += len(rows); part += 1
        print('  %s part-%05d  %s행' % (table, part - 1, format(len(rows), ',')))
        if not chunk or len(rows) < chunk:
            break

    print('✓ %-24s %8d행  →  gs://%s/%s  (%d파일)'
          % (table, total, args.bucket, dest_dir, part))
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tables', help='쉼표로 구분. 기본은 1·2순위 전체')
    ap.add_argument('--from', dest='date_from', help='증분 시작 (포함)')
    ap.add_argument('--to', dest='date_to', help='증분 끝 (제외)')
    ap.add_argument('--dt', help='GCS 폴더 날짜. 기본은 오늘(KST)')
    ap.add_argument('--full', action='store_true', help='기간 조건 없이 전량')
    ap.add_argument('--year', type=int, help='--full 과 함께. 운행을 연도로 자른다')
    ap.add_argument('--bucket', default=os.environ.get('GCS_BUCKET', 'cartax-biz_cartax_statistics'))
    ap.add_argument('--dry-run', action='store_true', help='접속하지 않고 SQL 만 출력')
    args = ap.parse_args()

    kst = datetime.timezone(datetime.timedelta(hours=9))
    today = datetime.datetime.now(kst).date()
    args.dt = args.dt or today.isoformat()
    if not args.full:
        args.date_to = args.date_to or today.isoformat()
        args.date_from = args.date_from or (today - datetime.timedelta(days=1)).isoformat()

    selects = parse_selects(SQL_DIR / '00_mysql_extract.sql')
    schemas = parse_schema(SQL_DIR / '02_raw_table.sql')

    tables = args.tables.split(',') if args.tables else DEFAULT_TABLES
    missing = [t for t in tables if t not in selects or TABLE_MAP.get(t) not in schemas]
    if missing:
        sys.exit('SQL 에서 찾을 수 없는 테이블: %s' % ', '.join(missing))

    conn = bucket = None
    if not args.dry_run:
        import pymysql
        from google.cloud import storage
        conn = pymysql.connect(
            host=os.environ['MYSQL_HOST'], port=int(os.environ.get('MYSQL_PORT', 3306)),
            user=os.environ['MYSQL_USER'], password=os.environ['MYSQL_PASSWORD'],
            database=os.environ['MYSQL_DB'], charset='utf8mb4')
        bucket = storage.Client().bucket(args.bucket)

    grand = 0
    for t in tables:
        grand += run_table(t, selects[t], schemas[TABLE_MAP[t]], args, conn, bucket)
    if not args.dry_run:
        conn.close()
        print('\n합계 %d행' % grand)


if __name__ == '__main__':
    main()
