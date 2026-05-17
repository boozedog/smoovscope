.PHONY: sidecar run-sidecar xcodeproj clean

sidecar:
	./scripts/build-sidecar.sh

run-sidecar:
	cd sidecar && go run .

xcodeproj:
	cd app && xcodegen generate

clean:
	rm -rf sidecar/bin app/Resources/otlp-receiver app/build app/DerivedData
