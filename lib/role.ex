alias Converge.{All, Util, FilePresent, User}

defmodule RoleSbuild do
	import Util, only: [conf_dir: 1, conf_file: 2, content: 1, path_expand_content: 1]
	Util.declare_external_resources("files")

	def role(tags \\ []) do
		# TODO: put builder user in sbuild group
		# TODO: do the initial setup:
		# as root:
		# sbuild-update --keygen
		#
		# as builder:
		# RELEASE=stretch
    	# mk-sbuild "$RELEASE"
    	# schroot --chroot source:"$RELEASE"-amd64 --user root --directory / -- apt-get update
    	# schroot --chroot source:"$RELEASE"-amd64 --user root --directory / -- apt-get dist-upgrade -V --no-install-recommends
    	# Install nano and less so that we can try to fix build failures
    	# schroot --chroot source:"$RELEASE"-amd64 --user root --directory / -- apt-get install eatmydata nano less
    	# (install eatmydata before installing sbuild-"$RELEASE"-amd64)
    	sbuild_default_distribution = Util.tag_value!(tags, "sbuild_default_distribution")
		%{
			desired_packages: [
				"sbuild",
				"schroot",
				"debootstrap",
				"debhelper",
				"ubuntu-dev-tools",
				"apt-cacher-ng",
				# Need rng-tools to get enough entropy to generate GPG key :/
				"rng-tools",
				"rsync",
				# Need autoconf for some things including erlang rules/debian:get-orig-source
				"autoconf",
				# Need kernel-wedge for building kernels
				"kernel-wedge",
				# Need fakeroot for building libtorrent
				"fakeroot",
			],
			post_install_unit: %All{units: [
				conf_file("/etc/sudoers", 0o440),
				conf_dir("/etc/schroot"),
				conf_dir("/etc/schroot/chroot.d"),
				conf_file("/etc/schroot/chroot.d/sbuild-xenial-amd64", 0o644),
				conf_file("/etc/schroot/chroot.d/sbuild-stretch-amd64", 0o644),
				%FilePresent{
					path:    "/home/builder/.sbuildrc",
					content: EEx.eval_string(content("files/home/builder/.sbuildrc.eex"), [sbuild_default_distribution: sbuild_default_distribution]),
					mode:    0o664,
					user:    "builder",
					group:   "builder",
				},
				%FilePresent{
					path:    "/home/builder/.mk-sbuild.rc",
					content: content("files/home/builder/.mk-sbuild.rc"),
					mode:    0o664,
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
