#!/usr/bin/perl
use strict;

# use warnings;
use 5.010;
use JSON::RPC::Client;
use JSON;
use LWP::UserAgent;
# use Data::Dumper;	# for debug

# CONFIG ################################################
my $APIURL = 'https://zabbix-server/api_jsonrpc.php';
my $APIUSER = 'zbx';
my $APIPASS = 'password';
my $ZABBIX_SENDER = '/usr/bin/zabbix_sender';
my $ZABBIX_SERVER = '127.0.0.1';
my $ZABBIX_PORT = '10051';	
my $KUBECTL = '/usr/bin/kubectl';
my $TMP_FILE_PATH = '/tmp/send_to_zabbix_'. int(rand(1000000000)) .'.data';

# LANG TOKENS ###########################################
my $JSON_PATH_NO_VALUE = 'No value';
#########################################################
# ITEMS WITH POSSIBLE EMPTY VALUES
my @JSON_PATHS_W_POSSIBLE_EMPTY_VALUES = (
    'status\.containerStatuses(name=.*)\.restartCount',
    'status\.containerStatuses(name=.*)\.ready',
    'status\.reason',
);

#########################################################

my $HOSTNAME = $ARGV[0];
my $CONFIG = $ARGV[1] || '/etc/zabbix/k8s.conf';
my $NAMESPACE = $ARGV[2] || 'kube-system';
my @NAMESPACES = split /,/,$NAMESPACE.',none';

#############################################
# Request to Zabbix API for data to collect #
#############################################
my $ID = 0;
my @ITEMS;
my %COLLECTED_DATA;
my %TO_ZABBIX;
my %NAMESPACES_HASH = map {$_ => 1} @NAMESPACES;
my %JSON_PATHS_W_POSSIBLE_EMPTY_VALUES = map {$_ => 1} @JSON_PATHS_W_POSSIBLE_EMPTY_VALUES; 
# Auth ######################################
# my $authRequest = (
#     jsonrpc => '2.0',
#     method  => 'user.login',
#     params  => {
#         user        => $APIUSER,
#         password    => $APIPASS,
#     },
#     id      => ++$ID,
# );
my $authRequestJson = {
	"jsonrpc" => "2.0",
	"method" => "user.login",
	"id" => ++$ID,
	"params" => {"user" => $APIUSER,"password" => $APIPASS}
};

my $respAuth;


my $client = new JSON::RPC::Client;
my $clientResponse;
$clientResponse = $client->call($APIURL, $authRequestJson);

die "Authentication failed\n" unless $clientResponse->content->{'result'};

my $AUTH = $clientResponse->content->{'result'};

# Get item list ##############################
my $postBody = {
    jsonrpc => '2.0',
    method  => 'item.get',
    params  => {
        output  => ['key_'],
        filter  =>  {
             host => $HOSTNAME,
        },
    },
    id      => ++$ID,
    auth    => $AUTH
};

my $clientResponse2 = $client->call($APIURL, $postBody);
die "Get items from zabbix failed\n" unless $clientResponse2->content->{'result'};

@ITEMS = map {$_ ->{key_}}  @{$clientResponse2->content->{'result'}};

################
# Collect data #
################

# Get data from Kubernetes
my %collected_data;
$ENV{'KUBECONFIG'} = $CONFIG;

foreach my $kind ('pods', 'nodes', 'services', 'deployments', 'apiservices', 'componentstatuses') {
    my $output = `$KUBECTL get $kind -o json --all-namespaces=true`;
    my $outJson = JSON::decode_json $output;
    push @{$collected_data{$kind}}, @{$outJson->{items}};
}


# Item keys tokenizer
my $ITEM_REGEXP = '^trap\.k8s\.';

foreach my $itemKey (@ITEMS) {
    my ($kind, $namespace, $name, $path) = $itemKey =~ m/$ITEM_REGEXP(.*)\[(.*),(.*),(.*)\]/;
    next if (rindex($itemKey, "trap.k8s.", 0) != 0);
    next if (!defined $kind || !defined $name || !defined $path);

    my @path = split('\.',$path);

    my $dataOfKind = $collected_data{$kind};
    foreach my $element (@$dataOfKind) {

        # if element has namespace, check if we really need this one and if its equal to current item
        if (defined $element->{metadata}->{namespace}) {
            next unless (
                defined $NAMESPACES_HASH{$element->{metadata}->{namespace}}
                and $element->{metadata}->{namespace} eq $namespace
            );
        }

        next unless ($element->{metadata}->{name} eq $name);

        my $value = get_value_by_path($element, \@path);
        $TO_ZABBIX{$itemKey} = $value;
        last;
    }
}

# Send collected data to Zabbix
send_to_zabbix($TMP_FILE_PATH,\%TO_ZABBIX);
unlink $TMP_FILE_PATH;

#########
# Funcs #
#########
# Recursively parse JSON path
sub get_value_by_path {
    my ($json, $path) = @_;
    
    my $element = shift @$path;

    # Check if expressions exists
    my ($key,$value);
    if ($element =~ m/=/) {
        ($key, $value) = $element =~ m/.+\((.+)=(.+)\)/;
        $element =~ s/(\w+).*/\1/;
    }

    if (scalar @$path > 0) {
        
        if (ref $json->{$element} eq 'ARRAY') {
            return "Key syntax invalid" if (!defined $key or !defined $value);

            # Search for index set in expression
            my $index;
            my @elementsArr = @{$json->{$element}};
            for(my $i=0; $i<=$#elementsArr; $i++) {
                if($elementsArr[$i]->{$key} eq $value) {
                    $index = $i;
                    last;
                }
            }

            # If index not defined, most probably path or expression is wrong
            if (defined $index) {
                get_value_by_path($json->{$element}->[$index], $path);
            } else {
                return $JSON_PATH_NO_VALUE;
            }

        } elsif(ref $json->{$element} eq 'HASH') {
            get_value_by_path($json->{$element}, $path);
        } else {
            return $JSON_PATH_NO_VALUE;
        }

    } else {
        (defined $json->{$element}) ? return $json->{$element} : return $JSON_PATH_NO_VALUE;
    }
}

sub send_to_zabbix {
    my ($tmpFilePath, $to_zabbix) = @_;
    open(my $fh, '>', $tmpFilePath);
    #map {print "$HOSTNAME $_ $to_zabbix->{$_}\n"} keys %$to_zabbix; # DEBUG
    foreach my $to_z (keys %$to_zabbix) {
        if ($to_zabbix->{$to_z} eq $JSON_PATH_NO_VALUE) {
            my @isNoValueAllowed = grep {$to_z =~ /$_/} @JSON_PATHS_W_POSSIBLE_EMPTY_VALUES;
            next if (scalar @isNoValueAllowed > 0);
        }
	my $key = $to_z;
        print $fh "$HOSTNAME $key $to_zabbix->{$to_z}\n";
    }
    close $fh;
    my $cmd = "$ZABBIX_SENDER -z $ZABBIX_SERVER -p $ZABBIX_PORT -i $tmpFilePath";
    # print $cmd."\n";
    my $ret = system($cmd);
    print "Zabbix sender return status = ".$ret."\n";
}
