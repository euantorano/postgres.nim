# postgres

A PostgreSQL client library for Nim. It features both a synchronous connection and an asynchronous one and aims to work fully with prepared statements.

*This is a work in progress, the only implemented features are:*

- [X] Connecting to server
    - [X] No authentication
    - [ ] Cleartext authentication
    - [ ] MD5 authentication
- [ ] Running queies
    - [X] Simple queries with no parameters
        - [ ] Queries using `COPY FROM STDIN` or any other type of copy
- [ ] Connection pool
