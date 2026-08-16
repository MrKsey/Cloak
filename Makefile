default: all

version=$(shell ver=$$(git log -n 1 --pretty=oneline --format=%D | awk -F, '{print $$1}' | awk '{print $$3}'); \
	if [ "$$ver" = "master" ] ; then \
	ver="master($$(git log -n 1 --pretty=oneline --format=%h))" ; \
	fi ; \
	echo $$ver)

GOFLAGS=-trimpath
LDFLAGS=-s -w

client: 
	mkdir -p build
	go build $(GOFLAGS) -ldflags "$(LDFLAGS) -X main.version=${version}" ./cmd/ck-client 
	mv ck-client* ./build

server: 
	mkdir -p build
	go build $(GOFLAGS) -ldflags "$(LDFLAGS) -X main.version=${version}" ./cmd/ck-server
	mv ck-server* ./build

install:
	mv build/ck-* /usr/local/bin

all: client server

clean:
	rm -rf ./build/ck-*
