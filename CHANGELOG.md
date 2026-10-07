# Changelog

All notable changes to this project are recorded here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- The iPhone 4S's Voice audio device with its input and output streams, formats,
  buffer, latencies and controls as a real device publishes them.
- `glReadPixels` reads RGBA bytes back from a framebuffer, a renderbuffer or the
  drawable, with the pack alignment and the rectangle clipped to the frame.
- A program made of GLSL ES 1.00 shaders that are not the compositor's is compiled, linked and
  run: the vertex shader per vertex, the fragment shader per pixel (uniforms, attributes, varyings,
  textures, `discard`, blending), for triangles. A varying the two shaders declare with another type
  or array size, or that only the fragment shader declares, fails the link; a draw with a program
  that did not link is an error. Core Image's OpenGL ES path draws with it.

### Changed
- The project is named Shade, and its JIT core Umbra: the namespace, build files,
  binary, file names and preference keys.
- The core is a separate submodule, `external/umbra`, and the Boost headers come
  from an independent repository.
- The device's class keys are derived under a new label; a device state saved
  before this is made again.

### Fixed
- OpenGL ES contexts are made on iOS 6.1.3's GLEngine, whose dispatch table is
  larger than the earlier ones: EAGLContext no longer answers nil.
- A memory object's purgeable state takes the whole state word (volatile with an
  ordering bit, a group), as the kernel does.
- `vm_remap` places memory into another task: Core Image's compiler daemon loads
  its kernels, so Core Image draws a source with alpha.
- The guest answers hw.activecpu, hw.physicalcpu, hw.logicalcpu, hw.cpufrequency,
  hw.busfrequency and their `_max` forms from the device profile, and hw.ncpu with
  the processor count the kernel has: OpenCL sized its CPU device from stack
  garbage, so Core Image's Gaussian blur (a one-dimensional kernel) drew nothing.
- The host's memory is read on macOS: the JIT sized its code cache from zeros.
- iOS 6.1.3 boots on the iPhone 4S with mediaserverd running: it needs the Voice
  device's input stream.
- The Vulkan Memory Allocator's README carries its own name, and NOTICE lists the
  allocator.

### Removed
- The configure-time test patch the JIT core already contained.
