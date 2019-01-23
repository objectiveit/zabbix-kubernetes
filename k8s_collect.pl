#!/usr/bin/perl
use strict;

use JSON;
use LWP::UserAgent;
use Data::Dumper;

# CONFIG ################################################
my $APIURL = 'http://127.0.0.1/zabbix/api_jsonrpc.php';
my $APIUSER = 'zabbixapi';
my $APIPASS = 'zabbixapipass';
my $ZABBIX_SENDER = '/usr/bin/zabbix_sender';
my $ZABBIX_SERVER = '127.0.0.1';
my $ZABBIX_PORT = '10051';
my $KUBECTL = '/usr/bin/kubectl';
my $TMP_FILE_PATH = '/tmp/send_to_zabbix.data';

# TOKENS ################################################
my $ITEM_REGEXP = '^trap\.k8s\.';
my $TOKEN_HEALTHCHECK = 'healthcheck';
#########################################################

my $HOSTNAME = $ARGV[0];
$ENV{'KUBECONFIG'} = $ARGV[1];

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
    die "Zabbix API HTTP Connection Error";
}

################
# Collect data #
################

# Get data from Kubernetes
foreach my $kind ('pods', 'nodes', 'services', 'deployments') {
    my $output = `$KUBECTL get $kind -o json`;
    my $outJson = decode_json $output;
    $COLLECTED_DATA{$kind} = $outJson->{items};
}

# Item keys tokenizer
foreach my $itemKey (@ITEMS) {
    my ($kind, $namespace, $name, $path) = $itemKey =~ m/$ITEM_REGEXP(.*)\[(.*),(.*),(.*)\]/;
    next if (!defined $kind || !defined $name || !defined $path);

    my $value;
    if ($name eq $TOKEN_HEALTHCHECK) {
        my (@json) = grep {$_->{metadata}->{namespace} eq $namespace} @{$COLLECTED_DATA{$kind}};
        $value = health_check_pods(\@json, $kind) if ($kind eq 'pods');
    } else {
        my @path = split('\.',$path);
        my ($json) = grep {$_->{metadata}->{name} eq $name} @{$COLLECTED_DATA{$kind}};
        $value = get_value_by_path($json, \@path);
    }
    $TO_ZABBIX{$itemKey} = $value;
}

# Send collected data to Zabbix
send_to_zabbix();

#########
# Funcs #
#########

# Health check for pods
sub health_check_pods {
    my ($json, $kind) = @_;

    if($kind eq 'pods') {
        my $inReadyStatus = 0;
        my $numberOfPods = scalar @$json;
        foreach my $pod (@$json) {
            my @ready = grep {$_->{type} eq 'Ready'} @{$pod->{status}->{conditions}};
            $inReadyStatus++ if ($ready[0]->{status} eq 'True');
        }
        ($inReadyStatus == $numberOfPods) ? return "OK" : return "Only $inReadyStatus of $numberOfPods are in Ready state";
    }

}

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
    open(my $fh, '>', $TMP_FILE_PATH);
    map {print $fh "$HOSTNAME $_ $TO_ZABBIX{$_}\n"} keys %TO_ZABBIX;
    close $fh;
    my $ret = system("$ZABBIX_SENDER -z $ZABBIX_SERVER -p $ZABBIX_PORT -i $TMP_FILE_PATH");
    print $ret;
}
