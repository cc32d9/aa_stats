CREATE DATABASE aa_stats;

CREATE USER 'aa_stats'@'localhost' IDENTIFIED BY 'Fao5Ohth';
GRANT ALL ON aa_stats.* TO 'aa_stats'@'localhost';
grant SELECT on aa_stats.* to 'aa_stats_ro'@'%' identified by 'aa_stats_ro';

use aa_stats;

CREATE TABLE SYNC
(
 network           VARCHAR(15) PRIMARY KEY,
 block_num         BIGINT NOT NULL
) ENGINE=InnoDB;


CREATE TABLE CLAIMDROP
(
 network       VARCHAR(15) NOT NULL,
 seq           BIGINT UNSIGNED NOT NULL,
 block_num     BIGINT NOT NULL,
 block_time    DATETIME NOT NULL,
 trx_id        VARCHAR(64) NOT NULL,
 claimer       VARCHAR(13) NOT NULL,
 drop_id       BIGINT UNSIGNED NOT NULL,
 claim_amount  INT UNSIGNED NOT NULL
)  ENGINE=InnoDB;

CREATE UNIQUE INDEX CLAIMDROP_I01 ON CLAIMDROP (network, seq);
CREATE INDEX CLAIMDROP_I02 ON CLAIMDROP (network, block_time);
CREATE INDEX CLAIMDROP_I03 ON CLAIMDROP (network, drop_id, block_time);
CREATE INDEX CLAIMDROP_I04 ON CLAIMDROP (network, claimer, block_time);
CREATE INDEX CLAIMDROP_I05 ON CLAIMDROP (trx_id(16));



CREATE TABLE MINTS
(
 network       VARCHAR(15) NOT NULL,
 seq           BIGINT UNSIGNED NOT NULL,
 block_num     BIGINT NOT NULL,
 block_time    DATETIME NOT NULL,
 trx_id        VARCHAR(64) NOT NULL,
 asset_id      BIGINT UNSIGNED NOT NULL,
 collection_name VARCHAR(13) NOT NULL,
 schema_name   VARCHAR(13) NOT NULL,
 template_id   BIGINT NOT NULL,
 owner         VARCHAR(13) NOT NULL
)  ENGINE=InnoDB;

CREATE UNIQUE INDEX MINTS_I01 ON MINTS (network, seq);
CREATE INDEX MINTS_I02 ON MINTS (network, block_time);
CREATE INDEX MINTS_I03 ON MINTS (network, asset_id, block_time);
CREATE INDEX MINTS_I04 ON MINTS (network, collection_name, block_time);
CREATE INDEX MINTS_I05 ON MINTS (network, owner, block_time);
CREATE INDEX MINTS_I06 ON MINTS (trx_id(16));


CREATE TABLE TRANSFERS
(
 network       VARCHAR(15) NOT NULL,
 seq           BIGINT UNSIGNED NOT NULL,
 block_num     BIGINT NOT NULL,
 block_time    DATETIME NOT NULL,
 trx_id        VARCHAR(64) NOT NULL,
 asset_id      BIGINT UNSIGNED NOT NULL,
 tx_from       VARCHAR(13) NOT NULL,
 tx_to         VARCHAR(13) NOT NULL,
 memo          VARCHAR(256) NOT NULL
)  ENGINE=InnoDB;

CREATE UNIQUE INDEX TRANSFERS_I01 ON TRANSFERS (network, seq, asset_id);
CREATE INDEX TRANSFERS_I02 ON TRANSFERS (network, block_time);
CREATE INDEX TRANSFERS_I03 ON TRANSFERS (network, asset_id, block_time);
CREATE INDEX TRANSFERS_I04 ON TRANSFERS (network, tx_from, block_time);
CREATE INDEX TRANSFERS_I05 ON TRANSFERS (network, tx_to, block_time);
CREATE INDEX TRANSFERS_I06 ON TRANSFERS (trx_id(16));


CREATE TABLE BURNS
(
 network       VARCHAR(15) NOT NULL,
 seq           BIGINT UNSIGNED NOT NULL,
 block_num     BIGINT NOT NULL,
 block_time    DATETIME NOT NULL,
 trx_id        VARCHAR(64) NOT NULL,
 asset_id      BIGINT UNSIGNED NOT NULL,
 owner         VARCHAR(13) NOT NULL
)  ENGINE=InnoDB;

CREATE UNIQUE INDEX BURNS_I01 ON BURNS (network, seq);
CREATE INDEX BURNS_I02 ON BURNS (network, block_time);
CREATE INDEX BURNS_I03 ON BURNS (network, asset_id, block_time);
CREATE INDEX BURNS_I04 ON BURNS (network, owner, block_time);
CREATE INDEX BURNS_I05 ON BURNS (trx_id(16));



