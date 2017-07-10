import postgres, unittest, asyncdispatch

suite "asynchronous tests":
  let connection = waitFor openAsync(user = "postgres", password = "password", database = "postgres")
  discard waitFor connection.execute("CREATE TABLE IF NOT EXISTS users (id serial PRIMARY KEY, name varchar(255) NOT NULL, age integer NOT NULL);")

  test "insert with raw query":
    let affectedRows = waitFor connection.execute("INSERT INTO users (name, age) VALUES ('euan', 1);")
    check affectedRows == 1

  test "delete with raw query":
    let affectedRows = waitFor connection.execute("DELETE FROM users WHERE name = 'euan';")
    check affectedRows == 1
