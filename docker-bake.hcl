target "docker-metadata-action" {}

target "build" {
  inherits = ["docker-metadata-action"]
  context = "./"
  dockerfile = "Dockerfile"
  platforms = [
    "linux/386",
    "linux/amd64",
    "linux/arm/v7",
    "linux/arm64/v8",
    "linux/mips64le",
    "linux/ppc64le",
    "linux/s390x"
  ]
}