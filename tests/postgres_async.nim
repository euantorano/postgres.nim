import postgres, unittest, asyncdispatch, terminal, os

suite "asynchronous tests":
  proc handleNotice(notice: PostgresMessage) =
    styledWriteLine(stdout, fgYellow, "  [NOTICE] ", resetStyle, "[", notice.notice.code, "] ", notice.notice.message)

  var host = getEnv("POSTGRES_HOST")
  if len(host) < 1:
    host = "localhost"

  let connection = waitFor openAsync(host = host, user = "postgres", password = "password", database = "postgres", noticeCallback = handleNotice)
  discard waitFor connection.execute("CREATE TABLE IF NOT EXISTS users (id serial PRIMARY KEY, name varchar(255) NOT NULL, age integer NOT NULL);")

  test "delete with raw query":
    let affectedRows = waitFor connection.execute("DELETE FROM users WHERE name = 'euan';")
    check affectedRows == 0

  test "insert with raw query":
    let affectedRows = waitFor connection.execute("INSERT INTO users (name, age) VALUES ('euan', 1);")
    check affectedRows == 1

  test "select with raw query":
    let reader = waitFor connection.query("SELECT name, age FROM users;")
    defer: waitFor reader.close()

    var
      name: string
      age: string
      numRows: int = 0
    while waitFor reader.read():
      check reader[0] == reader["name"]
      name = reader["name"]
      age = reader["age"]
      inc(numRows)

    check numRows == 1
    check name == "euan"
    check age == "1"

  test "delete with raw query after insert":
    let affectedRows = waitFor connection.execute("DELETE FROM users WHERE name = 'euan';")
    check affectedRows == 1

  test "prepare statement":
    let prepared = waitFor connection.prepare("SELECT * FROM users;")
