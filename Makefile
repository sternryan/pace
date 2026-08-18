.PHONY: test build run app install

test:
	swift test

build:
	swift build -c release

run:
	swift run Pace

app: build
	./Scripts/build-app.sh

install: app
	rm -rf "$$HOME/Applications/Pace.app"
	mkdir -p "$$HOME/Applications"
	cp -R .build/Pace.app "$$HOME/Applications/Pace.app"
	@echo "Installed to ~/Applications/Pace.app — launch it once manually, then enable Launch at Login in Preferences."
