#!/usr/bin/perl
use strict;

use JSON;
use Data::Dumper;

my $KUBECTL = "/usr/bin/kubectl";
$ENV{'KUBECONFIG'} = '/home/appliance/k8s_zabbix/config';

my $TYPE = $ARGV[0];
my $NAME = $ARGV[1];
my $JSON_PATH = $ARGV[2];
my @jsonPath = split('\.',$JSON_PATH);

my $cmd = "";
if ($TYPE eq 'pods') {
    $cmd = "$KUBECTL get pods -o json"
}

my $output = `$cmd`;
my $outJson = decode_json $output;

foreach my $item (@{$outJson->{items}}) {
    next if ($item->{metadata}->{name} ne $NAME);

    my $value = get_value_by_path($item,\@jsonPath);    
    print $value;
}

sub get_value_by_path {
    my ($json, $path) = @_;
    
    my $element = shift @$path;
    
    if (scalar @$path > 0) {
        get_value_by_path($json->{$element}, $path);
    } else {
        return $json->{$element};
    }
}
