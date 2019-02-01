#!/usr/bin/perl
use strict;

use JSON;
use Data::Dumper;

my $KUBECTL = "/usr/bin/kubectl";
$ENV{'KUBECONFIG'} = $ARGV[0];
my $DISCOVERY = $ARGV[1];
my $NAMESPACE = $ARGV[2] || undef;
my $HOSTNAME = $ARGV[3];

my $ZABBIX_SENDER = '/usr/bin/zabbix_sender';
my $ZABBIX_SERVER = '127.0.0.1';
my $ZABBIX_PORT = '10051';

# Change only if you changed key names in Zabbix template
my $ZABBIXKEY_NODATA_PODS = 'trap.k8s.discovery.nodata.pods';
my $ZABBIXKEY_NODATA_CONTAINERS = 'trap.k8s.discovery.nodata.containers';
my $ZABBIXKEY_NODATA_SERVICES = 'trap.k8s.discovery.nodata.services';
my $ZABBIXKEY_NODATA_DEPLOYMENTS = 'trap.k8s.discovery.nodata.deployments';

if ($DISCOVERY eq 'containers') {
    my $output = `$KUBECTL get pods -o json -n $NAMESPACE`;
    my $outJson = decode_json $output;
    my $result = discover_containers($outJson);

    (scalar @{$result->{data}} == 0) ? report_to_zabbix($ZABBIXKEY_NODATA_CONTAINERS, 1) : report_to_zabbix($ZABBIXKEY_NODATA_CONTAINERS, 0);

    #print Dumper($result);
    print encode_json $result;
}

if ($DISCOVERY eq 'pods') {
    my $output = `$KUBECTL get pods -o json -n $NAMESPACE`;
    my $outJson = decode_json $output;
    my $result = discover_pods($outJson);

    (scalar @{$result->{data}} == 0) ? report_to_zabbix($ZABBIXKEY_NODATA_PODS, 1) : report_to_zabbix($ZABBIXKEY_NODATA_PODS, 0);

    #print Dumper($result);
    print encode_json $result;
}

if ($DISCOVERY eq 'nodes') {
    my $output = `$KUBECTL get nodes -o json`;
    my $outJson = decode_json $output;
    my $result = discover_nodes($outJson);

    #print Dumper($result);
    print encode_json $result;
}

if ($DISCOVERY eq 'services') {
    my $output = `$KUBECTL get services -o json -n $NAMESPACE`;
    my $outJson = decode_json $output;
    my $result = discover_services($outJson);

    (scalar @{$result->{data}} == 0) ? report_to_zabbix($ZABBIXKEY_NODATA_SERVICES, 1) : report_to_zabbix($ZABBIXKEY_NODATA_SERVICES, 0);

    #print Dumper($result);
    print encode_json $result;
}

if ($DISCOVERY eq 'deployments') {
    my $output = `$KUBECTL get deployments -o json -n $NAMESPACE`;
    my $outJson = decode_json $output;
    my $result = discover_deployments($outJson);

    (scalar @{$result->{data}} == 0) ? report_to_zabbix($ZABBIXKEY_NODATA_DEPLOYMENTS, 1) : report_to_zabbix($ZABBIXKEY_NODATA_DEPLOYMENTS, 0);

    #print Dumper($result);
    print encode_json $result;
}

sub discover_deployments {
    my $json = shift;

    my $result = {
        data => [],              
    };

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
            '{#NAMESPACE}' => $item->{metadata}->{namespace},                                           
        };
        push @{$result->{data}},$discovery;                      
    }
    return $result;
}

sub discover_services {
    my $json = shift;

    my $result = {
        data => [],              
    };

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
            '{#NAMESPACE}' => $item->{metadata}->{namespace},
        };
        push @{$result->{data}},$discovery;
                      
    }
    return $result;
}

sub discover_nodes {
    my $json = shift;

    my $result = {
        data => [],
    };
    
    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
        };
        push @{$result->{data}},$discovery;
    }

    return $result;
}


sub discover_containers {
    my $json = shift;
    
    my $result = {
        data => [],
    };

    foreach my $item (@{$json->{items}}) {
        foreach my $container (@{$item->{spec}->{containers}}) {
            my $discovery = {
                '{#NAME}' => $item->{metadata}->{name},
                '{#NAMESPACE}' => $item->{metadata}->{namespace},
                '{#CONTAINER}' => $container->{name},
            };
            push @{$result->{data}},$discovery;
        }
    }

    return $result;
}

sub discover_pods {
    my $json = shift;
    
    my $result = {
        data => [],                     
    };

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
            '{#NAMESPACE}' => $item->{metadata}->{namespace},                                                                            
        };
        push @{$result->{data}},$discovery;
    }
    return $result;
}

sub report_to_zabbix {
    my ($key,$value) = @_;
    system("$ZABBIX_SENDER -z $ZABBIX_SERVER -p $ZABBIX_PORT -s $HOSTNAME -k $key -o $value 1>/dev/null");
}
