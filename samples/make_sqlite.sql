-- deterministic fixture db: authors, books, loans with fks, an index, a view,
-- one blob column, and a 100k-row notes table to exercise the count budget.
PRAGMA foreign_keys = ON;
CREATE TABLE authors (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  born INTEGER,
  country TEXT
);
CREATE TABLE books (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  author_id INTEGER NOT NULL REFERENCES authors(id),
  year INTEGER,
  pages INTEGER,
  price REAL,
  cover BLOB,
  isbn TEXT UNIQUE
);
CREATE TABLE loans (
  id INTEGER PRIMARY KEY,
  book_id INTEGER NOT NULL REFERENCES books(id),
  borrower TEXT NOT NULL,
  loaned_on TEXT NOT NULL,
  returned_on TEXT
);
CREATE TABLE notes (
  id INTEGER PRIMARY KEY,
  body TEXT NOT NULL
);
CREATE INDEX books_author_idx ON books(author_id);
CREATE INDEX loans_book_idx ON loans(book_id);
CREATE VIEW books_with_authors AS
  SELECT b.id, b.title, a.name AS author, b.year FROM books b JOIN authors a ON a.id = b.author_id;

WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 50)
INSERT INTO authors (id, name, born, country)
  SELECT n, 'Author ' || n, 1900 + (n * 7) % 90, CASE n % 4 WHEN 0 THEN 'NO' WHEN 1 THEN 'FR' WHEN 2 THEN 'JP' ELSE 'CA' END FROM seq;

WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 400)
INSERT INTO books (id, title, author_id, year, pages, price, cover, isbn)
  SELECT n, 'Book ' || n || CASE n % 3 WHEN 0 THEN ': a novel' WHEN 1 THEN ' (vol. ' || (n % 5 + 1) || ')' ELSE '' END,
         (n * 13) % 50 + 1, 1950 + (n * 3) % 75, 80 + (n * 37) % 600, ((n * 17) % 4000) / 100.0 + 5,
         CASE WHEN n % 10 = 0 THEN zeroblob(n * 3) ELSE NULL END,
         '978' || substr('0000000000' || (n * 7919), -10, 10)
  FROM seq;

WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 500)
INSERT INTO loans (id, book_id, borrower, loaned_on, returned_on)
  SELECT n, (n * 31) % 400 + 1, 'reader' || (n % 40), date('2024-01-01', '+' || (n * 2) || ' days'),
         CASE WHEN n % 3 = 0 THEN NULL ELSE date('2024-01-01', '+' || (n * 2 + 14) || ' days') END
  FROM seq;

WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 100000)
INSERT INTO notes (id, body) SELECT n, 'note number ' || n || ' with a little text so rows are not tiny' FROM seq;

PRAGMA user_version = 3;
