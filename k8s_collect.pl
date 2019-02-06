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
my $TMP_FILE_PATH = '/tmp/send_to_zabbix.data';

# LANG TOKENS ###########################################
my $ITEM_REGEXP = '^trap\.k8s\.';
my $TOKEN_HEALTHCHECK = 'healthcheck';
my %HEALTHZ_KEYs = {
    'healthz'               => 'trap.k8s.healthz',
    'bootstrap-controller'  => 'trap.k8s.bootstrap-controller',
    'third-party-resources' => 'trap.k8s.third-party-resources',
    'bootstrap-roles'       => 'trap.k8s.bootstrap-roles',
};
#########################################################

my $HOSTNAME = $ARGV[0];
my @CONFIGS = split /,/,$ARGV[1];
my @NAMESPACES = split /,/,$ARGV[2];

#############################################
# Request to Zabbix API for data to collect #
#############################################
my $ID = 0;
my $AUTH = '';
my @ITEMS;
my %COLLECTED_DATA;
my %TO_ZABBIX;

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
foreach my $config(@CONFIGS) {
    $ENV{'KUBECONFIG'} = $config;
    my %collected_data;
    my %to_zabbix;
    foreach my $namespace (@NAMESPACES) {
        foreach my $kind ('pods', 'nodes', 'services', 'deployments') {
            my $output = `$KUBECTL get $kind -o json -n $namespace`;
            my $outJson = decode_json $output;
            push @{$collected_data{$kind}}, @{$outJson->{items}};
        }

        # Item keys tokenizer
        foreach my $itemKey (@ITEMS) {
            my ($kind, $namespace, $name, $path) = $itemKey =~ m/$ITEM_REGEXP(.*)\[(.*),(.*),(.*)\]/;
            next if (!defined $kind || !defined $name || !defined $path);

            my @path = split('\.',$path);
            my ($json) = grep {$_->{metadata}->{name} eq $name} @{$collected_data{$kind}};
            my $value = get_value_by_path($json, \@path);
            $to_zabbix{$itemKey} = $value;
        }
        # Send collected data to Zabbix
        send_to_zabbix($TMP_FILE_PATH,\%to_zabbix);
    }
}
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
                return "JSON path is incorrect (inside array)";
            }

        } elsif(ref $json->{$element} eq 'HASH') {

            get_value_by_path($json->{$element}, $path);

        } else {
            return "JSON path is incorrect";
        }

    } else {
        return $json->{$element};
    }
}

sub send_to_zabbix {
    my ($tmpFilePath, $to_zabbix) = @_;
    open(my $fh, '>', $tmpFilePath);
    #map {print "$HOSTNAME $_ $to_zabbix->{$_}\n"} keys %$to_zabbix; # DEBUG
    map {print $fh "$HOSTNAME $_ $to_zabbix->{$_}\n"} keys %$to_zabbix;
    close $fh;
    my $ret = system("$ZABBIX_SENDER -z $ZABBIX_SERVER -p $ZABBIX_PORT -i $tmpFilePath");
    print $ret;
}
