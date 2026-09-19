# Changelog

All notable changes to this project are recorded here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- The iPhone 4S's Voice audio device with its input and output streams, formats,
  buffer, latencies and controls as a real device publishes them.

### Changed
- The project is named Shade, and its JIT core Umbra: the namespace, build files,
  binary, file names and preference keys.
- The core is a separate submodule, `external/umbra`, and the Boost headers come
  from an independent repository.
- The device's class keys are derived under a new label; a device state saved
  before this is made again.

### Fixed
- The host's memory is read on macOS: the JIT sized its code cache from zeros.
- iOS 6.1.3 boots on the iPhone 4S with mediaserverd running: it needs the Voice
  device's input stream.
- The Vulkan Memory Allocator's README carries its own name, and NOTICE lists the
  allocator.

### Removed
- The configure-time test patch the JIT core already contained.
