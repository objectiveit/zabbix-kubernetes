#!/usr/bin/perl 
use strict;

use LWP::UserAgent;
use MIME::Base64;
use JSON;

my $HOST = $ARGV[0];
my $PORT = $ARGV[1];
$ENV{'KUBECONFIG'} = $ARGV[2];

my $KUBECTL = '/usr/bin/kubectl';

my %HEALTHZ_URLs = {
    'healthz'                 => '/healthz',
    'bootstrap-controller'    => '/healthz/poststarthook/bootstrap-controller',
    'third-party-resources'   => '/healthz/poststarthook/extensions/third-party-resources',
    'bootstrap-roles'         => '/healthz/poststarthook/rbac/bootstrap-roles',
};

my $TOKEN;
my $secretsOutput = `$KUBECTL get secrets -o json`;
my $secretsJson = decode_json $secretsOutput;
foreach my $secret (@{$secretsJson->{items}}) {
    next unless $secret->{metadata}->{annotations}->{"kubernetes.io/service-account.name"} eq 'default';
    $TOKEN = decode_base64($secret->{data}->{token});
    last;
}

my $k8sua = LWP::UserAgent->new();
$k8sua->ssl_opts(
        verify_hostname => 0,
);

$k8sua->default_header(Authorization => "Bearer $TOKEN");
foreach my $healthPath (keys %HEALTHZ_URLs) {
    my $resp = $k8sua->get("https://$HOST:$PORT/    $healthPath");
    print $resp->content();
}
