#!/usr/bin/perl
use strict;

use JSON;
use Data::Dumper;

my $KUBECTL = "/usr/bin/kubectl";
#$ENV{'KUBECONFIG'}
my @CONFIGS = split /,/,$ARGV[0];
my $DISCOVERY = $ARGV[1];
my @NAMESPACES = split /,/,$ARGV[2] || undef;
my $HOSTNAME = $ARGV[3];

my $ZABBIX_SENDER = '/usr/bin/zabbix_sender';
my $ZABBIX_SERVER = '127.0.0.1';
my $ZABBIX_PORT = '10051';

# Change only if you changed key names in Zabbix template
my $ZABBIXKEY_NODATA_PODS = 'trap.k8s.discovery.nodata.pods';
my $ZABBIXKEY_NODATA_CONTAINERS = 'trap.k8s.discovery.nodata.containers';
my $ZABBIXKEY_NODATA_SERVICES = 'trap.k8s.discovery.nodata.services';
my $ZABBIXKEY_NODATA_DEPLOYMENTS = 'trap.k8s.discovery.nodata.deployments';
my $ZABBIXKEY_NODATA_NODES = 'trap.k8s.discovery.nodata.nodes';
my $ZABBIXKEY_NODATA_APISERVICES = 'trap.k8s.discovery.nodata.apiservices';
my $ZABBIXKEY_NODATA_COMPONENTSTATUSES = 'trap.k8s.discovery.nodata.componentstatuses';
my $ZABBIXKEY_NODATA_CLUSTERS = 'trap.k8s.discovery.nodata.nodes';

my @RESULT;
my $ZABBIXKEY;

foreach my $config (@CONFIGS) {
    $ENV{'KUBECONFIG'} = $config;
    foreach my $ns (@NAMESPACES) {
        if ($DISCOVERY eq 'clusters') {
            my $output = `$KUBECTL config view -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_clusters($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_CLUSTERS;
        }
        elsif ($DISCOVERY eq 'apiservices') {
            my $output = `$KUBECTL get apiservices -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_apiservices($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_APISERVICES;
        }
        elsif ($DISCOVERY eq 'componentstatuses') {
            my $output = `$KUBECTL get componentstatuses -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_componentstatuses($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_COMPONENTSTATUSES;
        }
        elsif ($DISCOVERY eq 'containers') {
            my $output = `$KUBECTL get pods -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_containers($outJson);
            
            $ZABBIXKEY = $ZABBIXKEY_NODATA_CONTAINERS;

            #print Dumper($result);
        }
        elsif ($DISCOVERY eq 'pods') {
            my $output = `$KUBECTL get pods -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_pods($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_PODS;
            #print Dumper($result);
        }

        elsif ($DISCOVERY eq 'nodes') {
            my $output = `$KUBECTL get nodes -o json`;
            my $outJson = decode_json $output;
            my $result = discover_nodes($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_NODES;
            #print Dumper($result);
        }

        elsif ($DISCOVERY eq 'services') {
            my $output = `$KUBECTL get services -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_services($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_SERVICES;
            #print Dumper($result);
        }

        elsif ($DISCOVERY eq 'deployments') {
            my $output = `$KUBECTL get deployments -o json -n $ns`;
            my $outJson = decode_json $output;
            my $result = discover_deployments($outJson);

            $ZABBIXKEY = $ZABBIXKEY_NODATA_SERVICES;
            #print Dumper($result);
        }
        else {
            die "Only pods,services,deployments and containers are supported";
        }
    }
}

# Report to Zabbix and print out discovery data
(length @RESULT == 0) ? report_to_zabbix($ZABBIXKEY, 1) : report_to_zabbix($ZABBIXKEY, 0);
print encode_json get_uniq();

sub get_uniq {
    my %uniq = ();

    foreach my $value (@RESULT) {
        my $key = "";
        
        if (defined $value->{'{#NAMESPACE}'}) {
            $key .= $value->{'{#NAMESPACE}'} . '::' 
        }
        
        $key .= $value->{'{#NAME}'};
        next if defined $uniq{$key};
        $uniq{$key} = $value;
    }

    my $toZabbix = {
        data => [],
    };

    push @{$toZabbix->{data}},values %uniq;

    return $toZabbix;
}

sub discover_clusters {
    my $json = shift;

    foreach my $item (@{$json->{clusters}}) {
        my $discovery = {
            '{#NAME}' => $item->{name},
            '{#APIURL}' => $item->{cluster}->{server},
        };
        push @RESULT,$discovery;
    }
}

sub discover_apiservices {
    my $json = shift;

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
        };
        push @RESULT,$discovery;
    }
    return;
}

sub discover_componentstatuses {
    my $json = shift;

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
        };
        push @RESULT,$discovery;
    }

    return;
}

sub discover_deployments {
    my $json = shift;

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
            '{#NAMESPACE}' => $item->{metadata}->{namespace},                                           
        };
        push @RESULT,$discovery;                      
    }
    return;
}

sub discover_services {
    my $json = shift;

    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
            '{#NAMESPACE}' => $item->{metadata}->{namespace},
        };
        push @RESULT,$discovery;
                      
    }
    return;
}

sub discover_nodes {
    my $json = shift;
    
    foreach my $item (@{$json->{items}}) {
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
        };
        push @RESULT,$discovery;
    }

    return;
}


sub discover_containers {
    my $json = shift;

    foreach my $item (@{$json->{items}}) {
        foreach my $container (@{$item->{spec}->{containers}}) {
            my $discovery = {
                '{#NAME}' => $item->{metadata}->{name},
                '{#NAMESPACE}' => $item->{metadata}->{namespace},
                '{#CONTAINER}' => $container->{name},
            };
            push @RESULT,$discovery;
        }
    }

    return;
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
        push @RESULT,$discovery;
    }
    return;
}

sub report_to_zabbix {
    my ($key,$value) = @_;
    system("$ZABBIX_SENDER -z $ZABBIX_SERVER -p $ZABBIX_PORT -s $HOSTNAME -k $key -o $value 1>/dev/null");
}
