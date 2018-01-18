alias Converge.{All, Util, FilePresent, DirectoryPresent, User}

defmodule RoleSbuild do
	import Util, only: [conf_file: 2, content: 1, path_expand_content: 1]
	Util.declare_external_resources("files")

	def role(tags \\ []) do
		# TODO: put builder user in sbuild group

		# How to do the initial setup:
		_ =
		"""
		# as root:
		sbuild-adduser builder
		rngd -r /dev/urandom
		cat /etc/apt/sources.list | grep -v "http://packages:" > /home/builder/sources.list
		chown builder:builder /home/builder/sources.list

		# as builder:
		cd
		sbuild-update --keygen

		RELEASE=stretch
		for ARCH in amd64 i386; do
			# Install git because we stuff .git into tarballs and various packages
			# (xfsprogs, notmuch) expect git to be installed when .git is present
			#
			# Install nano and less so that we can try to fix build failures
			mk-sbuild --arch=$ARCH --eatmydata --debootstrap-include=git,nano,less "$RELEASE"
			cat ~/stretch_apt_preferences                                 | schroot --chroot source:"$RELEASE"-"$ARCH" --user root --directory / -- bash -c "cat > /etc/apt/preferences;  chmod a+r /etc/apt/preferences"
			# https -> http for apt-cacher-ng support
			cat ~/sources.list            | sed -r 's,https://,http://,g' | schroot --chroot source:"$RELEASE"-"$ARCH" --user root --directory / -- bash -c "cat > /etc/apt/sources.list; chmod a+r /etc/apt/sources.list"
			schroot --chroot source:"$RELEASE"-"$ARCH" --user root --directory / -- apt-get update
			schroot --chroot source:"$RELEASE"-"$ARCH" --user root --directory / -- apt-get dist-upgrade -V --no-install-recommends -y
		done
		"""
		sbuild_default_distribution = Util.tag_value!(tags, "sbuild_default_distribution")
		release                     = Util.tag_value!(tags, "release")
		%{
			apt_pins: [
				%{package: "debhelper", pin: "release n=#{release}-backports", pin_priority: 990}
			],
			desired_packages: [
				"sbuild",
				"ccache",
				"schroot",
				"debootstrap",
				"debhelper (>= 11)",
				"distro-info",  # mk-sbuild needs debian-distro-info and ubuntu-distro-info
				"apt-cacher-ng",
				"rng-tools",    # to get enough entropy to generate GPG key
				"rsync",
				"autoconf",     # for some things including erlang rules/debian:get-orig-source
				"kernel-wedge", # for building kernels
				"fakeroot",     # for building libtorrent
			],
			# mk-sbuild tries to modprobe overlayfs instead of overlay
			boot_time_kernel_modules: ["overlay"],
			post_install_unit: %All{units: [
				conf_file("/etc/sudoers", 0o440),
				%FilePresent{
					path:    "/home/builder/.zshenv",
					content: content("files/home/builder/.zshenv"),
					mode:    0o640,
					user:    "builder",
					group:   "builder",
				},
				%FilePresent{
					path:    "/home/builder/.sbuildrc",
					content: EEx.eval_string(content("files/home/builder/.sbuildrc.eex"), [sbuild_default_distribution: sbuild_default_distribution]),
					mode:    0o640,
					user:    "builder",
					group:   "builder",
				},
				%FilePresent{
					path:    "/home/builder/.mk-sbuild.rc",
					content: content("files/home/builder/.mk-sbuild.rc"),
					mode:    0o640,
					user:    "builder",
					group:   "builder",
				},
				%FilePresent{
					path:    "/home/builder/stretch_apt_preferences",
					content: content("files/home/builder/stretch_apt_preferences"),
					mode:    0o640,
					user:    "builder",
					group:   "builder",
				},
				%DirectoryPresent{
					path:    "/home/builder/bin",
					mode:    0o750,
					user:    "builder",
					group:   "builder",
				},
				%FilePresent{
					path:    "/home/builder/bin/make-tarball-for-sbuild",
					content: content("files/home/builder/bin/make-tarball-for-sbuild"),
					mode:    0o750,
					user:    "builder",
					group:   "builder",
				},
				%FilePresent{
					path:    "/home/builder/bin/free-up-disk-for-sbuild",
					content: content("files/home/builder/bin/free-up-disk-for-sbuild"),
					mode:    0o750,
					user:    "builder",
					group:   "builder",
				},
				# Install our fixed mk-sbuild to ~/bin that tries to use overlay instead of overlayfs.
				# Without this fix, mk-sbuild from ubuntu-dev-tools would use aufs instead of overlay.
				%FilePresent{
					path:    "/home/builder/bin/mk-sbuild",
					content: content("files/home/builder/bin/mk-sbuild"),
					mode:    0o750,
					user:    "builder",
					group:   "builder",
				},
			]},
			ferm_output_chain:
				"""
				outerface lo {
					# {apt, debootstrap} -> apt-cacher-ng
					daddr 127.0.0.1 proto tcp syn dport 3142 {
						mod owner uid-owner (_apt root) ACCEPT;
					}

					# apt-cacher-ng -> custom-packages-server
					daddr 127.0.0.1 proto tcp syn dport 28000 {
						mod owner uid-owner apt-cacher-ng ACCEPT;
					}

					# Loopback connections are necessary for running the git test
					# suite, golang test suite, and possibly for other packages.
					daddr 127.0.0.1 proto (tcp udp icmp) {
						mod owner uid-owner builder ACCEPT;
					}
				}
				""",
			regular_users: [
				%User{
					name:  "builder",
					home:  "/home/builder",
					shell: "/bin/zsh",
					authorized_keys: [
						path_expand_content("~/.ssh/id_rsa.pub") |> String.trim_trailing
					]
				}
			],
		}
	end
end
