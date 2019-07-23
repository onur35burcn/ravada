package Ravada::Front::Domain::KVM;

use Data::Dumper;
use Hash::Util qw(lock_hash unlock_hash);
use Moose;
use XML::LibXML;

use Ravada::Utils;

extends 'Ravada::Front::Domain';

no warnings "experimental::signatures";
use feature qw(signatures);

our %GET_CONTROLLER_SUB = (
    usb => \&_get_controller_usb
    ,disk => \&_get_controller_disk
     ,screen => \&_get_controller_screen
    ,network => \&_get_controller_network
    );

our %GET_DRIVER_SUB = (
    network => \&_get_driver_network
     ,sound => \&_get_driver_sound
     ,video => \&_get_driver_video
     ,image => \&_get_driver_image
     ,jpeg => \&_get_driver_jpeg
     ,zlib => \&_get_driver_zlib
     ,playback => \&_get_driver_playback
     ,streaming => \&_get_driver_streaming
     ,disk => \&_get_driver_disk
     ,screen => \&_get_driver_screen
);


sub get_controller_by_name($self, $name) {
    return $GET_CONTROLLER_SUB{$name};
}

sub list_controllers($self) {
    return %GET_CONTROLLER_SUB;
}

sub _get_controller_usb {
	my $self = shift;
    my $doc = XML::LibXML->load_xml(string => $self->xml_description);
    
    my @ret;
    
    for my $controller ($doc->findnodes('/domain/devices/redirdev')) {
        next if $controller->getAttribute('bus') ne 'usb';
        
        push @ret,('type="'.$controller->getAttribute('type').'"');
    } 

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

sub _get_controller_disk($self) {
    return $self->list_volumes_info();
}

sub _get_controller_network($self) {
    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    my @ret;

    my $count = 0;
    for my $interface ($doc->findnodes('/domain/devices/interface')) {
        next if $interface->getAttribute('type') !~ /^(bridge|network)/;

        my ($model) = $interface->findnodes('model') or die "No model";
        my ($source) = $interface->findnodes('source') or die "No source";
        my $type = 'NAT';
        $type = 'bridge' if $source->getAttribute('bridge');
        my ($address) = $interface->findnodes('address');
        my $name = "en";
        if ($address->getAttribute('type') eq 'pci') {
            my $slot = $address->getAttribute('slot');
            $name .="s".hex($slot);
        } else {
            $name .="o$count";
        }
        $count++;
        push @ret,({
                     type => $type
                    ,name => $name
                  ,driver => $model->getAttribute('type')
                  ,bridge => $source->getAttribute('bridge')
                 ,network => $source->getAttribute('network')
        });
    }

    return @ret;
}

sub _get_controller_screen($self) {
    return ( $self->_get_controller_screen_spice()
            ,$self->_get_controller_screen_type('x2go')
        );
}

sub _get_controller_screen_spice($self) {
    my $xml = XML::LibXML->load_xml(string => $self->xml_description);

    my ($graph) = $xml->findnodes('/domain/devices/graphics')
        or return;

    my ($type) = $graph->getAttribute('type');
    my ($port) = $graph->getAttribute('port');
    my ($tls_port) = $graph->getAttribute('tlsPort');
    my ($address) = $graph->getAttribute('listen');

    die $self->name.$graph->toString if$self->is_active && !defined $port;

    my $display;
    $display = $type."://$address:$port" if defined $port;

    my %display = (
                driver => $type
               ,port => $port
                 ,ip => $address
            ,display => $display
          ,tls_port => $tls_port
     ,file_extension => 'vv'
    );

    my ($password) = $graph->getAttribute('passwd');
    $display{password} = $password if defined $password;

    lock_hash(%display);

    return (\%display);
}

=head2 get_driver

Gets the value of a driver

Argument: name

    my $driver = $domain->get_driver('video');

=cut

sub get_driver {
    my $self = shift;
    my $name = shift;

    my $sub = $GET_DRIVER_SUB{$name};

    die "I can't get driver $name for domain ".$self->name
        if !$sub;

    $self->xml_description if ref($self) !~ /Front/;

    return $sub->($self);
}

sub _get_driver_generic {
    my $self = shift;
    my $xml_path = shift;

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    for my $driver ($doc->findnodes($xml_path)) {
        my $str = $driver->toString;
        $str =~ s{^<$tag (.*)/>}{$1};
        push @ret,($str);
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
}

sub _get_driver_graphics {
    my $self = shift;
    my $xml_path = shift;

    my ($tag) = $xml_path =~ m{.*/(.*)};

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    for my $tags (qw(image jpeg zlib playback streaming)){
        for my $driver ($doc->findnodes($xml_path)) {
            my $str = $driver->toString;
            $str =~ s{^<$tag (.*)/>}{$1};
            push @ret,($str);
        }
    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;
    }
}

sub _get_driver_image {
    my $self = shift;

    my $image = $self->_get_driver_graphics('/domain/devices/graphics/image',@_);
#
#    if ( !defined $image ) {
#        my $doc = XML::LibXML->load_xml(string => $self->domain->get_xml_description);
#        Ravada::VM::KVM::xml_add_graphics_image($doc);
#    }
    return $image;
}

sub _get_driver_jpeg {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/jpeg',@_);
}

sub _get_driver_zlib {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/zlib',@_);
}

sub _get_driver_playback {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/playback',@_);
}

sub _get_driver_streaming {
    my $self = shift;
    return $self->_get_driver_graphics('/domain/devices/graphics/streaming',@_);
}

sub _get_driver_video {
    my $self = shift;
    return $self->_get_driver_generic('/domain/devices/video/model',@_);
}

sub _get_driver_network {
    my $self = shift;
    return $self->_get_driver_generic('/domain/devices/interface/model',@_);
}

sub _get_driver_sound {
    my $self = shift;
    my $xml_path ="/domain/devices/sound";

    my @ret;
    my $doc = XML::LibXML->load_xml(string => $self->xml_description);

    for my $driver ($doc->findnodes($xml_path)) {
        push @ret,('model="'.$driver->getAttribute('model').'"');
    }

    return $ret[0] if !wantarray && scalar@ret <2;
    return @ret;

}

sub _get_driver_disk {
    my $self = shift;
    my @volumes = $self->list_volumes_info();
    return $volumes[0]->{driver};
}

sub _get_driver_screen($self) {
    return $self->_get_driver_hardware('screen');
}

sub _get_driver_hardware($self, $hardware) {
    my $info = $self->info(Ravada::Utils::user_daemon);
    return $info->{hardware}->{$hardware}->[0]->{driver};
}

sub _default_screen_type { 'spice' }

sub xml_description($self, $inactive=undef) {
    if (!defined $inactive) {
        if (!$self->is_active) {
            $inactive=1;
        } else {
            $inactive=0;
        }
    }
    my $field = 'xml';
    $field = "xml_inactive" if $inactive;
    return $self->_data_extra($field);
}

1;
