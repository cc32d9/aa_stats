# install dependencies:
#  sudo apt install cpanminus libjson-xs-perl libjson-perl libmysqlclient-dev libdbi-perl
#  sudo cpanm Net::WebSocket::Server
#  sudo cpanm DBD::MariaDB

use strict;
use warnings;
use JSON;
use Getopt::Long;
use DBI;
use Time::HiRes qw (time);
use Time::Local 'timegm_nocheck';

use Net::WebSocket::Server;
use Protocol::WebSocket::Frame;

$Protocol::WebSocket::Frame::MAX_PAYLOAD_SIZE = 100*1024*1024;
$Protocol::WebSocket::Frame::MAX_FRAGMENTS_AMOUNT = 102400;

$| = 1;

my $network;

my $port = 8800;

my $dsn = 'DBI:MariaDB:database=aa_stats;host=localhost';
my $db_user = 'aa_stats';
my $db_password = 'Fao5Ohth';
my $commit_every = 10;
my $endblock = 2**32 - 1;

my $aacontract = 'atomicassets';
my $dropscontract = 'atomicdropsx';

my $ok = GetOptions
    ('network=s' => \$network,
     'port=i'    => \$port,
     'ack=i'     => \$commit_every,
     'endblock=i'  => \$endblock,
     'dsn=s'     => \$dsn,
     'dbuser=s'  => \$db_user,
     'dbpw=s'    => \$db_password,
     'aacontract=s'    => \$aacontract,
     'dropscontract=s' => \$dropscontract,
    );


if( not $network or not $ok or scalar(@ARGV) > 0 )
{
    print STDERR "Usage: $0 --network=X [options...]\n",
        "Options:\n",
        "  --network=X        network name\n",
        "  --port=N           \[$port\] TCP port to listen to websocket connection\n",
        "  --ack=N            \[$commit_every\] Send acknowledgements every N blocks\n",
        "  --endblock=N       \[$endblock\] Stop before given block\n",
        "  --dsn=DSN          \[$dsn\]\n",
        "  --dbuser=USER      \[$db_user\]\n",
        "  --dbpw=PASSWORD    \[$db_password\]\n";
    exit 1;
}


my $dbh = DBI->connect($dsn, $db_user, $db_password,
                       {'RaiseError' => 1, AutoCommit => 0,
                        mariadb_server_prepare => 1});
die($DBI::errstr) unless $dbh;

my $sth_upd_sync = $dbh->prepare
    ('INSERT INTO SYNC (network, block_num, block_time) VALUES(?,?,?) ' .
     'ON DUPLICATE KEY UPDATE block_num=?, block_time=?');

my $sth_add_claimdrop = $dbh->prepare
    ('INSERT IGNORE INTO CLAIMDROP ' .
     '(network, seq, block_num, block_time, trx_id, claimer, drop_id, claim_amount, country, whitelisted) ' .
     'VALUES(?,?,?,?,?,?,?,?,?,?)');

my $sth_add_claimdropkey = $dbh->prepare
    ('INSERT IGNORE INTO CLAIMDROPKEY ' .
     '(network, seq, block_num, block_time, trx_id, claimer, drop_id, claim_amount, referer, country) ' .
     'VALUES(?,?,?,?,?,?,?,?,?,?)');


my $sth_add_mint = $dbh->prepare
    ('INSERT IGNORE INTO MINTS ' .
     '(network, seq, block_num, block_time, trx_id, asset_id, collection_name, ' .
     'schema_name, template_id, owner) ' .
     'VALUES(?,?,?,?,?,?,?,?,?,?)');

my $sth_add_xfer = $dbh->prepare
    ('INSERT IGNORE INTO TRANSFERS ' .
     '(network, seq, block_num, block_time, trx_id, asset_id, tx_from, tx_to, memo) ' .
     'VALUES(?,?,?,?,?,?,?,?,?)');

my $sth_add_burn = $dbh->prepare
    ('INSERT IGNORE INTO BURNS ' .
     '(network, seq, block_num, block_time, trx_id, asset_id, owner) ' .
     'VALUES(?,?,?,?,?,?,?)');

my $committed_block = 0;
my $stored_block = 0;
my $uncommitted_block = 0;
{
    my $sth = $dbh->prepare
        ('SELECT block_num FROM SYNC WHERE network=?');
    $sth->execute($network);
    my $r = $sth->fetchall_arrayref();
    if( scalar(@{$r}) > 0 )
    {
        $stored_block = $r->[0][0];
        printf STDERR ("Starting from stored_block=%d\n", $stored_block);
    }
}



my $json = JSON->new;

my $blocks_counter = 0;
my $counter_start = time();


Net::WebSocket::Server->new(
    listen => $port,
    on_connect => sub {
        my ($serv, $conn) = @_;
        $conn->on(
            'binary' => sub {
                my ($conn, $msg) = @_;
                my ($msgtype, $opts, $js) = unpack('VVa*', $msg);
                my $data = eval {$json->decode($js)};
                if( $@ )
                {
                    print STDERR $@, "\n\n";
                    print STDERR $js, "\n";
                    exit;
                }

                my $ack = process_data($msgtype, $data);
                if( $ack >= 0 )
                {
                    $conn->send_binary(sprintf("%d", $ack));
                    print STDERR "ack $ack\n";
                }

                if( $ack >= $endblock )
                {
                    print STDERR "Reached end block\n";
                    exit(0);
                }
            },
            'disconnect' => sub {
                my ($conn, $code) = @_;
                print STDERR "Disconnected: $code\n";
                $dbh->rollback();
                $committed_block = 0;
                $uncommitted_block = 0;
            },

            );
    },
    )->start;


sub process_data
{
    my $msgtype = shift;
    my $data = shift;

    if( $msgtype == 1001 ) # CHRONICLE_MSGTYPE_FORK
    {
        my $block_num = $data->{'block_num'};
        print STDERR "fork at $block_num\n";
        $uncommitted_block = 0;
        return $block_num-1;
    }
    elsif( $msgtype == 1003 ) # CHRONICLE_MSGTYPE_TX_TRACE
    {
        if( $data->{'block_num'} > $stored_block )
        {
            my $trace = $data->{'trace'};
            if( $trace->{'status'} eq 'executed' )
            {
                my $block_time = $data->{'block_timestamp'};
                $block_time =~ s/T/ /;

                my $tx = {
                    'block_num' => $data->{'block_num'},
                    'block_time' => $block_time,
                    'trx_id' => $trace->{'id'},
                };

                foreach my $atrace (@{$trace->{'action_traces'}})
                {
                    process_atrace($tx, $atrace);
                }
            }
        }
    }
    elsif( $msgtype == 1010 ) # CHRONICLE_MSGTYPE_BLOCK_COMPLETED
    {
        $blocks_counter++;
        $uncommitted_block = $data->{'block_num'};
        if( $uncommitted_block - $committed_block >= $commit_every or
            $uncommitted_block >= $endblock )
        {
            $committed_block = $uncommitted_block;

            my $gap = 0;
            {
                my ($year, $mon, $mday, $hour, $min, $sec, $msec) =
                    split(/[-:.T]/, $data->{'block_timestamp'});
                my $epoch = timegm_nocheck($sec, $min, $hour, $mday, $mon-1, $year);
                $gap = (time() - $epoch)/3600.0;
            }

            my $period = time() - $counter_start;
            printf STDERR ("blocks/s: %8.2f, gap: %8.2fh, ",
                           $blocks_counter/$period, $gap);
            $counter_start = time();
            $blocks_counter = 0;

            if( $uncommitted_block > $stored_block )
            {
                my $block_time = $data->{'block_timestamp'};
                $block_time =~ s/T/ /;
                $sth_upd_sync->execute($network, $uncommitted_block, $block_time, $uncommitted_block, $block_time);
                $dbh->commit();
                $stored_block = $uncommitted_block;
            }
            return $committed_block;
        }
    }

    return -1;
}


sub process_atrace
{
    my $tx = shift;
    my $atrace = shift;

    my $act = $atrace->{'act'};
    my $contract = $act->{'account'};
    my $receipt = $atrace->{'receipt'};

    if( $receipt->{'receiver'} eq $contract )
    {
        my $aname = $act->{'name'};
        my $data = $act->{'data'};
        return unless ( ref($data) eq 'HASH' );

        if( $contract eq $aacontract )
        {
            if( $aname eq 'logmint' )
            {
                $sth_add_mint->execute($network,
                                       $receipt->{'global_sequence'},
                                       $tx->{'block_num'},
                                       $tx->{'block_time'},
                                       $tx->{'trx_id'},
                                       $data->{'asset_id'},
                                       $data->{'collection_name'},
                                       $data->{'schema_name'},
                                       $data->{'template_id'},
                                       $data->{'new_asset_owner'});
                printf STDERR ('!');
            }
            elsif( $aname eq 'logtransfer' )
            {
                foreach my $id (@{$data->{'asset_ids'}})
                {
                    $sth_add_xfer->execute($network,
                                           $receipt->{'global_sequence'},
                                           $tx->{'block_num'},
                                           $tx->{'block_time'},
                                           $tx->{'trx_id'},
                                           $id,
                                           $data->{'from'},
                                           $data->{'to'},
                                           $data->{'memo'});
                }
                printf STDERR ('>');
            }
            elsif( $aname eq 'logburnasset' )
            {
                $sth_add_burn->execute($network,
                                       $receipt->{'global_sequence'},
                                       $tx->{'block_num'},
                                       $tx->{'block_time'},
                                       $tx->{'trx_id'},
                                       $data->{'asset_id'},
                                       $data->{'asset_owner'});
                printf STDERR ('-');
            }
        }
        elsif( $contract eq $dropscontract )
        {
            if( $aname eq 'claimdrop' or $aname eq 'claimdropwl' )
            {
                my $wl = ($aname eq 'claimdropwl') ? 1:0;
                $sth_add_claimdrop->execute($network,
                                            $receipt->{'global_sequence'},
                                            $tx->{'block_num'},
                                            $tx->{'block_time'},
                                            $tx->{'trx_id'},
                                            $data->{'claimer'},
                                            $data->{'drop_id'},
                                            $data->{'claim_amount'},
                                            $data->{'country'},
                                            $wl);
                printf STDERR ($wl ? '.' : '_');
            }
            elsif( $aname eq 'claimdropkey' )
            {
                $sth_add_claimdropkey->execute($network,
                                               $receipt->{'global_sequence'},
                                               $tx->{'block_num'},
                                               $tx->{'block_time'},
                                               $tx->{'trx_id'},
                                               $data->{'claimer'},
                                               $data->{'drop_id'},
                                               $data->{'claim_amount'},
                                               $data->{'referer'},
                                               $data->{'country'});
                printf STDERR ('#');
            }
        }
    }
}
