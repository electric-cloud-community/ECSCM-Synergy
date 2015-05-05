####################################################################
#
# ECSCM::Synergy::Cfg: Object definition of CC  configuration.
#
####################################################################
package ECSCM::Synergy::Cfg;
@ISA = (ECSCM::Base::Cfg);
if (!defined ECSCM::Base::Cfg) {
    require ECSCM::Base::Cfg;
}


####################################################################
# Object constructor for ECSCM::Synergy::Cfg
#
# Inputs
#   cmdr  = a previously initialized ElectricCommander handle
#   name  = a name for this configuration
####################################################################
sub new {
    my $class = shift;

    my $cmdr = shift;
    my $name = shift;

    my($self) = ECSCM::Base::Cfg->new($cmdr,"$name");
    bless ($self, $class);
    return $self;
}

####################################################################
# synergyUserId
####################################################################
sub getSynergyUserId {
    my ($self) = @_;
    return $self->getUser();
}
sub setSynergyUserId {
    my ($self, $name) = @_;
    print "Setting synergyUserId to $name\n";
    return $self->setUser("$name");
}

####################################################################
# synergyPassword
####################################################################
sub getSynergyPassword {
    my ($self) = @_;
    return $self->getPassword();
}
sub setSynergyPassword {
    my ($self, $name) = @_;
    print "Setting synergyPassword to ***\n";
    return $self->setPassword("$name");
}

####################################################################
# synergyUserRole
####################################################################
sub getSynergyUserRole {
    my ($self) = @_;
    return $self->get("SynergyUserRole");
}
sub setSynergyUserRole {
    my ($self, $name) = @_;
    print "Setting SynergyUserRole to $name\n";
    return $self->set("SynergyUserRole", "$name");
}

####################################################################
# synergyCredential
####################################################################
sub getSynergyCredential {
    my ($self) = @_;
    return $self->getCredential();
}
sub setSynergyCredential {
    my ($self, $name) = @_;
    print "Setting SynergyCredential to $name\n";
    return $self->setCredential("$name");
}
1;

