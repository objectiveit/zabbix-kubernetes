#!/usr/bin/perl
use strict;

use JSON;
use LWP::UserAgent;
#use Data::Dumper;

# CONFIG ################################################
my $APIURL = 'http://127.0.0.1/zabbix/api_jsonrpc.php';
my $APIUSER = 'zabbixapi';
my $APIPASS = 'zabbixapipass';
my $ZABBIX_SENDER = '/usr/bin/zabbix_sender';
my $ZABBIX_SERVER = '127.0.0.1';
my $ZABBIX_PORT = '10051';
my $KUBECTL = '/usr/bin/kubectl';
my $TMP_FILE_PATH = '/tmp/send_to_zabbix_'. int(rand(1000000000)) .'.data';

# LANG TOKENS ###########################################
my $ITEM_REGEXP = '^trap\.k8s\.';
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
my $CONFIG = $ARGV[1];
my @NAMESPACES = split /,/,$ARGV[2].',none';

#############################################
# Request to Zabbix API for data to collect #
#############################################
my $ID = 0;
my $AUTH = '';
my @ITEMS;
my %COLLECTED_DATA;
my %TO_ZABBIX;
my %NAMESPACES_HASH = map {$_ => 1} @NAMESPACES;
my %JSON_PATHS_W_POSSIBLE_EMPTY_VALUES = map {$_ => 1} @JSON_PATHS_W_POSSIBLE_EMPTY_VALUES; 
my $ua = LWP::UserAgent->new();
$ua-> default_header('Content-Type' => 'application/json-rpc');
# Auth ######################################
my $authRequest = {
    jsonrpc => '2.0',
    method  => 'user.login',
    params  => {
        user        => $APIUSER,
        password    => $APIPASS,
    },
    id      => ++$ID,
};
my $authRequestJson = encode_json $authRequest;

my $respAuth = $ua->post($APIURL, Content => $authRequestJson);
if ($respAuth->is_success) {
    my $responseJson = decode_json $respAuth->content;
    $AUTH = $responseJson->{result};
    die "Zabbix API Authentication Error" if length $AUTH == 0;
} else {
    die "Zabbix API HTTP Connection Error";
}
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
my $postBodyJson = encode_json $postBody;
my $respItems = $ua->post($APIURL, Content => $postBodyJson);
if ($respItems->is_success) {
    my $responseJson = decode_json $respItems->content;
    @ITEMS = map {$_->{key_}} @{$responseJson->{result}}
} else {
    die "Zabbix API HTTP Co nnection Error";
}

################
# Collect data #
################

# Get data from Kubernetes
my %collected_data;
$ENV{'KUBECONFIG'} = $CONFIG;

foreach my $kind ('pods', 'nodes', 'services', 'deployments', 'apiservices', 'componentstatuses') {
    my $output = `$KUBECTL get $kind -o json --all-namespaces=true`;
    my $outJson = decode_json $output;
    push @{$collected_data{$kind}}, @{$outJson->{items}};
}

# Item keys tokenizer
foreach my $itemKey (@ITEMS) {
    my ($kind, $namespace, $name, $path) = $itemKey =~ m/$ITEM_REGEXP(.*)\[(.*),(.*),(.*)\]/;
    next if (!defined $kind || !defined $name || !defined $path);

    my @path = split('\.',$path);

    my $dataOfKind = $collected_data{$kind};
    foreach my $element (@$dataOfKind) {
        my $value;

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
        print $fh "$HOSTNAME $to_z $to_zabbix->{$to_z}\n";
        #print "$HOSTNAME $to_z $to_zabbix->{$to_z}\n";
    }
    close $fh;
    my $ret = system("$ZABBIX_SENDER -z $ZABBIX_SERVER -p $ZABBIX_PORT -i $tmpFilePath");
    print $ret;
}
