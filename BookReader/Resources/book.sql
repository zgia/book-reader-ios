PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

-- 表：book
DROP TABLE IF EXISTS book;

CREATE TABLE IF NOT EXISTS book (
    id         BIGINT,
    categoryid BIGINT,
    title      TEXT,
    alias      TEXT,
    authorid   BIGINT,
    summary    TEXT,
    source     TEXT,
    latest     TEXT,
    rate       BIGINT,
    wordcount  BIGINT,
    isfinished BIGINT,
    cover      TEXT,
    createdat  BIGINT,
    updatedat  BIGINT,
    deletedat  BIGINT
);


-- 表：book_author
DROP TABLE IF EXISTS book_author;

CREATE TABLE IF NOT EXISTS book_author (
    id          BIGINT,
    name        TEXT,
    former_name TEXT,
    createdat   BIGINT,
    updatedat   BIGINT,
    deletedat   BIGINT
);


-- 表：category
DROP TABLE IF EXISTS category;

CREATE TABLE IF NOT EXISTS category (
    id       BIGINT,
    parentid BIGINT,
    title    TEXT
);


-- 表：chapter
DROP TABLE IF EXISTS chapter;

CREATE TABLE IF NOT EXISTS chapter (
    id        BIGINT,
    bookid    BIGINT,
    volumeid  BIGINT,
    title     TEXT,
    wordcount BIGINT,
    createdat BIGINT,
    updatedat BIGINT,
    deletedat BIGINT
);


-- 表：content
DROP TABLE IF EXISTS content;

CREATE TABLE IF NOT EXISTS content (
    chapterid BIGINT,
    txt       TEXT
);


-- 表：user
DROP TABLE IF EXISTS user;

CREATE TABLE IF NOT EXISTS user (
    id         BIGINT,
    username   TEXT,
    realname   TEXT,
    mobile     TEXT,
    password   TEXT,
    salt       TEXT,
    lastip     TEXT,
    lastrealip TEXT,
    createdat  BIGINT,
    updatedat  BIGINT,
    deletedat  BIGINT
);


-- 表：volume
DROP TABLE IF EXISTS volume;

CREATE TABLE IF NOT EXISTS volume (
    id        BIGINT,
    bookid    BIGINT,
    title     TEXT,
    summary   TEXT,
    cover     TEXT,
    createdat BIGINT,
    updatedat BIGINT,
    deletedat BIGINT
);


COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
