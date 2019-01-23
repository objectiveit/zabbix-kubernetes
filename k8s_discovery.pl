#!/usr/bin/perl
use strict;

use JSON;
use Data::Dumper;

my $KUBECTL = "/usr/bin/kubectl";
$ENV{'KUBECONFIG'} = $ARGV[0];

my $DISCOVERY = $ARGV[1];
my $NAMESPACE = $ARGV[2] || undef;

my $result = {
    data => [],
};

if ($DISCOVERY eq 'containers') {
    my $output = `$KUBECTL get pods -o json`;
    my $outJson = decode_json $output;
    my $result = discover_containers($outJson, $NAMESPACE);

    #print Dumper($result);
    print encode_json $result;
}

if ($DISCOVERY eq 'pods') {
    my $output = `$KUBECTL get pods -o json`;
    my $outJson = decode_json $output;
    my $result = discover_pods($outJson, $NAMESPACE);

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
    my $output = `$KUBECTL get services -o json`;
    my $outJson = decode_json $output;
    my $result = discover_services($outJson, $NAMESPACE);

    #print Dumper($result);
    print encode_json $result;
}

if ($DISCOVERY eq 'deployments') {
    my $output = `$KUBECTL get deployments -o json`;
    my $outJson = decode_json $output;
    my $result = discover_deployments($outJson, $NAMESPACE);

    #print Dumper($result);
    print encode_json $result;
}

sub discover_deployments {
    my $json = shift;
    my $namespace = shift;

    my $result = {
        data => [],              
    };

    foreach my $item (@{$json->{items}}) {
        if (defined $namespace) {
            next if $namespace ne $item->{metadata}->{namespace};
        }
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
    my $namespace = shift;

    my $result = {
        data => [],              
    };

    foreach my $item (@{$json->{items}}) {
        if (defined $namespace) {
            next if $namespace ne $item->{metadata}->{namespace};                      
        }
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
    my $namespace = shift;
    
    my $result = {
        data => [],
    };

    foreach my $item (@{$json->{items}}) {
        foreach my $container (@{$item->{spec}->{containers}}) {
            if (defined $namespace) {
                next if $namespace ne $item->{metadata}->{namespace};                      
            }
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
    my $namespace = shift;
    
    my $result = {
        data => [],                     
    };

    foreach my $item (@{$json->{items}}) {
        if (defined $namespace) {
            next if $namespace ne $item->{metadata}->{namespace};                                  
        }
        my $discovery = {
            '{#NAME}' => $item->{metadata}->{name},
            '{#NAMESPACE}' => $item->{metadata}->{namespace},                                                                            
        };
        push @{$result->{data}},$discovery;
    }
    return $result;
}

