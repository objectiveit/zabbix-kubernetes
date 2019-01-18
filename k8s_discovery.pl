#!/usr/bin/perl
use strict;

use JSON;
use Data::Dumper;

my $KUBECTL = "/usr/bin/kubectl";
$ENV{'KUBECONFIG'} = "/home/appliance/k8s_zabbix/config";

my $DISCOVERY = $ARGV[1];

if ($DISCOVERY eq 'pods') {
    my $output = `$KUBECTL get pods -o json`;
    my $outJson = decode_json $output;
    my $result = fillin_discovery_data($outJson);

    print encode_json $result;
}

sub fillin_discovery_data {
    my $json = shift;
    
    my $result = {
        data => [],
    };

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name}
        };
        push @{$result->{data}},$discovery;
    }

    return $result;
}
