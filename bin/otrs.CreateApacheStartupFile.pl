#!/usr/bin/perl
# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';
use lib dirname($RealBin) . '/Custom';

use Getopt::Std qw();
use File::Find qw();

use Kernel::Config;
use Kernel::System::Encode;
use Kernel::System::Log;
use Kernel::System::Main;
use Kernel::System::Time;
use Kernel::System::DB;
use Kernel::Language;
use Kernel::System::SysConfig;

sub PrintUsage {
    print <<"EOF";

otrs.CreateApacheStartupFile.pl - update apache startup file for mod_perl
Copyright (C) 2001-2013 OTRS AG, http://otrs.com/

EOF
}

{

    # common objects
    my %CommonObject = ();
    $CommonObject{ConfigObject} = Kernel::Config->new();
    $CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
    $CommonObject{LogObject}    = Kernel::System::Log->new(
        LogPrefix => 'OTRS-otrs.CreateApacheStartupFile.pl',
        %CommonObject,
    );
    $CommonObject{MainObject} = Kernel::System::Main->new(%CommonObject);
    $CommonObject{TimeObject} = Kernel::System::Time->new(%CommonObject);
    $CommonObject{DBObject}   = Kernel::System::DB->new(%CommonObject);

    my $Home = $CommonObject{ConfigObject}->Get('Home');

    #
    # Loop over all general system packages and include them
    #
    my $PackagesCode = '';
    for my $Package ( GetPackageList( CommonObject => \%CommonObject ) ) {
        $PackagesCode .= "use $Package;\n";
    }

    #
    # Generate final output
    #
    my $Content = <<"EOF";
#!/usr/bin/perl
# -\-
# scripts/apache-perl-startup.pl - to load the modules if mod_perl is used
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# -\-
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# -\-

#
# THIS FILE IS AUTOGENERATED BY otrs.CreateApacheStartupFile.pl
#

use strict;
use warnings;

BEGIN {
    # switch to unload_package_xs, the PP version is broken in Perl 5.10.1.
    # see http://rt.perl.org/rt3//Public/Bug/Display.html?id=72866
    \$ModPerl::Util::DEFAULT_UNLOAD_METHOD = 'unload_package_xs';    ## no critic

    # set \$0 to index.pl if it is not an existing file:
    # on Fedora, $0 is not a path which would break OTRS.
    # see bug # 8533
    if ( !-e \$0 ) {
        \$0 = '$Home/bin/cgi-bin/index.pl';
    }
}

use ModPerl::Util;

# set otrs lib path!
use lib "$Home";
use lib "$Home/Kernel/cpan-lib";
use lib "$Home/Custom";

use CGI ();
CGI->compile(':cgi');
use CGI::Carp ();

$PackagesCode

1;
EOF

    print "Writing file $Home/scripts/apache2-perl-startup2.pl\n";

    $CommonObject{MainObject}->FileWrite(
        Location => "$Home/scripts/apache2-perl-startup2.pl",
        Content  => \$Content,
    );
}

=item GetPackageList()

=cut

sub GetPackageList {
    my %Param        = @_;
    my %CommonObject = %{ $Param{CommonObject} };

    my @Packages = ( 'Apache::DBI', 'Kernel::Config' );

    my $DBType = $CommonObject{DBObject}->GetDatabaseFunction('Type');
    if ( $DBType eq 'mysql' ) {
        push @Packages, 'DBD::mysql', 'Kernel::System::DB::mysql';
    }
    elsif ( $DBType =~ /postgresql/smxi ) {
        push @Packages, 'DBD::Pg', 'Kernel::System::DB::postgresql';
    }
    elsif ( $DBType =~ /postgresql_before_8_2/smxi ) {
        push @Packages, 'DBD::Pg', 'Kernel::System::DB::postgresql_before_8_2';
    }
    elsif ( $DBType eq 'oracle' ) {
        push @Packages, 'DBD::Oracle', 'Kernel::System::DB::oracle';
    }

    my $Home = $CommonObject{ConfigObject}->Get('Home');

    # add all language files for configued languages
    my $Languages = $CommonObject{ConfigObject}->Get('DefaultUsedLanguages');
    for my $Language ( sort keys %{$Languages} ) {
        my @LanguageFiles = $CommonObject{MainObject}->DirectoryRead(
            Directory => "$Home/Kernel/Language",
            Filter    => "$Language*.pm",
        );
        for my $LanguageFile ( sort @LanguageFiles ) {
            my $Package = CheckPerlPackage(
                CommonObject => \%CommonObject,
                Filename     => $LanguageFile,
            );
            next FILE if !$Package;
            push @Packages, $Package;
        }
    }

    # Directories to check
    my @Directories = (
        "$Home/Kernel/GenericInterface",
        "$Home/Kernel/Modules",
        "$Home/Kernel/Output",
        "$Home/Kernel/System",
    );

    # Ignore patterns. These modules can possibly not be loaded on all systems.
    my @Excludes = (
        "Kernel/System/DB",
        "LDAP",
        "Radius",
        "IMAP",
        "POP3",
        "SMTP",
        "UnitTest",
    );

    my @Files;

    my $Wanted = sub {
        return if $File::Find::name !~ m{\.pm$}smx;
        for my $Exclude (@Excludes) {
            return if $File::Find::name =~ m{\Q$Exclude\E}smx;
        }
        push @Files, $File::Find::name;
    };

    for my $Directory (@Directories) {
        File::Find::find( $Wanted, $Directory );
    }

    FILE:
    for my $File ( sort @Files ) {
        my $Package = CheckPerlPackage(
            CommonObject => \%CommonObject,
            Filename     => $File,
        );
        next FILE if !$Package;
        push @Packages, $Package;
    }

    return @Packages;
}

=item CheckPerlPackage()

checks if a given file is a valid OTRS Perl package.

    my $Package = CheckPerlPackage(
        CommonObject => \%CommonObject,
        Filename => $File
    );

This function will extract the package name, and check if the package
is really defined in the given file.

Returns the package name, if it is valid, undef otherwise.

=cut

sub CheckPerlPackage {
    my %Param        = @_;
    my %CommonObject = %{ $Param{CommonObject} };
    my $Filename     = $Param{Filename};

    my $Home = $CommonObject{ConfigObject}->Get('Home');

    # Generate package name
    my $PackageName = substr( $Filename, length($Home) );
    $PackageName =~ s{^/|\.pm$}{}smxg;
    $PackageName =~ s{/}{::}smxg;

    # Check if the file really contains the package
    my $FileContent = $CommonObject{MainObject}->FileRead(
        Location => $Filename,
    );
    return if !ref $FileContent;
    return if ( ${$FileContent} !~ /^package\s+\Q$PackageName\E/smx );

    # Check if the package compiles ok
    return if ( !$CommonObject{MainObject}->Require($PackageName) );

    return $PackageName;
}

exit 0;
