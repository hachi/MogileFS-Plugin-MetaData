name:      perl-MogileFS-Plugin-MetaData
summary:   perl-MogileFS-Plugin-MetaData - MogileFS Tracker plugin to store extra metadata along with a particular file.
version:   0.01
release:   1
vendor:    Jonathan Steinert <hachi@cpan.org>
packager:  Jonathan Steinert <hachi@cpan.org>
license:   Artistic
group:     Applications/CPAN
buildroot: %{_tmppath}/%{name}-%{version}-%(id -u -n)
buildarch: noarch
source:    MogileFS-Plugin-MetaData-%{version}.tar.gz
requires:  perl-MogileFS-Plugin-MetaData

%description
MogileFS Tracker plugin to store extra metadata along with a particular file.

%prep
rm -rf "%{buildroot}"
%setup -n MogileFS-Plugin-MetaData-%{version}

%build
%{__perl} Makefile.PL PREFIX=%{buildroot}%{_prefix}
make all
make test

%install
make pure_install

[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress


# remove special files
find %{buildroot} \(                    \
       -name "perllocal.pod"            \
    -o -name ".packlist"                \
    -o -name "*.bs"                     \
    \) -exec rm -f {} \;

# no empty directories
find %{buildroot}%{_prefix}             \
    -type d -depth -empty               \
    -exec rmdir {} \;

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files
%defattr(-,root,root)
%{_prefix}/lib/*
