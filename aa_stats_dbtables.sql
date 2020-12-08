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


