# slbounce: an EFI driver that starts Linux in EL2 on Snapdragon X laptops through
# Secure Launch (Windows' tcblaunch.exe), which makes KVM possible. Used by
# omnibook-kvm. Built from the release tarball (it includes the git submodules).
Name:           slbounce
Version:        5
Release:        2%{?dist}
Summary:        Start Linux in EL2 (KVM) on Windows-on-Arm laptops via Secure Launch
License:        BSD-3-Clause AND BSD-2-Clause AND MIT
URL:            https://github.com/TravMurav/slbounce
Source0:        %{url}/releases/download/v%{version}/slbounce-v%{version}.tar.gz
ExclusiveArch:  aarch64

BuildRequires:  gcc
BuildRequires:  binutils
BuildRequires:  make
BuildRequires:  glibc-devel

# Freestanding EFI binaries: Fedora's compiler flags (hardening, LTO) and debuginfo
# don't apply.
%undefine _auto_set_build_flags
%global debug_package %{nil}

%description
slbounce.efi is an EFI runtime driver: loaded before the OS loader, it hooks
ExitBootServices and, when the device tree is an EL2 one (zap shader disabled),
uses Secure Launch to take over EL2 instead of Qualcomm's hypervisor. sltest.efi
only tests the switch.

%prep
echo "36ac7fbc257d5777c48c0a4f9d1e39d27804f6d7b80033160b70e54fcaeb7310  %{SOURCE0}" | sha256sum -c
%autosetup -n slbounce-v%{version}
# No banner at every boot (slbounce is loaded at every boot, before GRUB); errors still print.
sed -i '/Print(L"===\[ slbounce \]/,/Print(L"=====/d' src/bounce_main.c
! grep -q 'slbounce \]' src/bounce_main.c

%build
# Native build: the Makefile defaults to a cross compiler. Not parallel: its two
# gnu-efi targets each run gnu-efi's make and would race.
make CROSS_COMPILE=

%install
install -Dm0644 -t %{buildroot}%{_prefix}/lib/slbounce out/slbounce.efi out/sltest.efi

%files
%license LICENSE
%doc README.md
%{_prefix}/lib/slbounce/
