.PHONY: sidecar run-sidecar run-app xcodeproj clean

sidecar:
	./scripts/build-sidecar.sh

run-sidecar:
	cd sidecar && go run .

run-app:
	bash ./scripts/run-app.sh

xcodeproj:
	cd app && xcodegen generate

clean:
	rm -rf sidecar/bin app/Resources/otlp-receiver app/build app/DerivedData
