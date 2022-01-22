# Global build arg
ARG INSTALL_ZSH=false
ARG INSTALL_GO=false
ARG GIT_USERNAME
ARG GIT_EMAIL

# Note: You can use any Debian/Ubuntu based image you want. 
# FROM mcr.microsoft.com/vscode/devcontainers/base:0-bullseye
FROM docker:20.10.12-dind as dind-rootless

# busybox "ip" is insufficient:
#   [rootlesskit:child ] error: executing [[ip tuntap add name tap0 mode tap] [ip link set tap0 address 02:50:00:00:00:01]]: exit status 1
# Install apk packages
RUN apk add --no-cache iproute2 bash zsh zsh-vcs curl yq jq git sudo

# "/run/user/UID" will be used by default as the value of XDG_RUNTIME_DIR
RUN mkdir /run/user && chmod 1777 /run/user

# create a default user preconfigured for running rootless dockerd
RUN set -eux; \
	adduser -h /home/vscode -g 'vscode' -D -u 1000 vscode; \
	echo 'vscode:100000:65536' >> /etc/subuid; \
	echo 'vscode:100000:65536' >> /etc/subgid

RUN set -eux; \
	\
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		'x86_64') \
			url='https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-20.10.12.tgz'; \
			;; \
		'aarch64') \
			url='https://download.docker.com/linux/static/stable/aarch64/docker-rootless-extras-20.10.12.tgz'; \
			;; \
		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;; \
	esac; \
	\
	wget -O rootless.tgz "$url"; \
	\
	tar --extract \
		--file rootless.tgz \
		--strip-components 1 \
		--directory /usr/local/bin/ \
		'docker-rootless-extras/rootlesskit' \
		'docker-rootless-extras/rootlesskit-docker-proxy' \
		'docker-rootless-extras/vpnkit' \
	; \
	rm rootless.tgz; \
	\
	rootlesskit --version; \
	vpnkit --version

# pre-create "/var/lib/docker" for our vscode user
RUN set -eux; \
	mkdir -p /home/vscode/.local/share/docker; \
	chown -R vscode:vscode /home/vscode/.local/share/docker
VOLUME /home/vscode/.local/share/docker



FROM dind-rootless as sudo_setup

USER root

# Add user vscode to sudoers
RUN passwd vscode -d
RUN echo "vscode ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vscode



FROM sudo_setup as zsh_setup

# Do user level environment setup
USER vscode

# Install oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install spaceship-prompt(oh-my-zsh installation method)
ENV ZSH_CUSTOM=/home/vscode/.oh-my-zsh/
RUN git clone https://github.com/spaceship-prompt/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
RUN ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
RUN sed -i 's/^ZSH_THEME=.*$/ZSH_THEME=\"spaceship\"/g' ~/.zshrc; 



FROM zsh_setup as install_package

# build arg
ARG INSTALL_GO

USER root

# Install go
ENV PATH="${PATH}:/usr/local/go/bin"
WORKDIR /root
COPY library-scripts/install_go.sh install_go.sh
RUN	if [ ${INSTALL_GO} == true ]; then ./install_go.sh; fi; 




FROM install_package as userenv_setup

USER vscode

# Change DOCKER_HOST env
ENV DOCKER_HOST=unix:///run/user/1000/docker.sock

# Set default shell to zsh
ENV SHELL=zsh

# Set git userinfo for showing in commit log
ARG GIT_USERNAME
ARG GIT_EMAIL
RUN if [ ! -z $GIT_USERNAME ] && [ ! -z $GIT_EMAIL ] ; then \
	git config --global user.name $GIT_USERNAME; \
	git config --global user.email $GIT_EMAIL; \
	fi
	
ENTRYPOINT ["/usr/local/bin/dockerd-entrypoint.sh"]







