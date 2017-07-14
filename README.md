# postgres [![CircleCI](https://circleci.com/gh/euantorano/postgres.nim.svg?style=svg)](https://circleci.com/gh/euantorano/postgres.nim)

A PostgreSQL client library for Nim. It features both a synchronous connection and an asynchronous one and aims to work fully with prepared statements.

**This is a work in progress, the only implemented features are:**

- [X] Connecting to server
    - [X] No authentication
    - [X] Cleartext authentication
    - [X] MD5 authentication
    - Other authentication methods (KerberosV5, ScmCredential, GssApi, Sppi and GssApiOrSppiData) are not planned to be implemented
- [ ] Running queies
    - [X] Simple queries with no parameters
        - [ ] Queries using `COPY FROM STDIN` or any other type of copy
        - [X] Queries that return no results
        - [ ] Queries that return a result set
            - [X] Basic reading of results
            - [ ] Handling columns of different types
    - [ ] Prepared statements with bound parameters
- [ ] Connection pool

## [Documentation](https://htmlpreview.github.io/?https://github.com/euantorano/postgres.nim/blob/master/docs/postgres.html)
