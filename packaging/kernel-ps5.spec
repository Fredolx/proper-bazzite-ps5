%global debug_package %{nil}
%global _build_id_links none
%global __os_install_post %{nil}
%global __strip /bin/true

Name:           kernel-ps5
Version:        %{ver}
Release:        1%{?dist}
Summary:        PS5 Linux kernel %{kver}
License:        GPL-2.0-only
URL:            https://kernel.org
ExclusiveArch:  x86_64
AutoReqProv:    no

Provides:       kernel = %{ver}
Provides:       kernel-core = %{ver}
Provides:       kernel-modules = %{ver}
Provides:       kernel-devel = %{ver}

%description
Linux kernel %{kver} with PlayStation 5 support patches.

%install
cp -a %{stagedir}/. %{buildroot}/

%files
/boot/vmlinuz-%{kver}
/boot/System.map-%{kver}
/boot/config-%{kver}
/usr/lib/modules/%{kver}
/usr/bin/ps5_control

%post
depmod -a %{kver} || true
