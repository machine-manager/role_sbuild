alias Converge.{All, FilePresent}

defmodule RoleSbuild do
	import Converge.Util, only: [conf_file: 2, content: 1]

	def role(_tags \\ []) do
		# TODO: create sbuild user
		# TODO: create builder user
		# TODO: do the initial setup:
		# sbuild-update --keygen
    	# mk-sbuild xenial
    	# schroot --chroot source:xenial-amd64 --user root --directory / -- apt-get update
    	# schroot --chroot source:xenial-amd64 --user root --directory / -- apt-get dist-upgrade -V --no-install-recommends
    	# Install nano and less so that we can try to fix build failures
    	# schroot --chroot source:xenial-amd64 --user root --directory / -- apt-get install eatmydata nano less
    	# (install eatmydata before installing sbuild-xenial-amd64)
		%{
			desired_packages: [
				"sbuild",
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
			],
			post_install_unit: %All{units: [
				conf_file("/etc/sudoers", 0o440),
				conf_file("/etc/schroot/chroot.d/sbuild-xenial-amd64", 0o644),
				%FilePresent{
					path:    "/home/builder/.sbuildrc",
					content: content("files/home/builder/.sbuildrc"),
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
		}
	end
end
