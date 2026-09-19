# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

add_library(shade_filesystem STATIC hfs_metadata.cpp hfs_volume_layout.cpp)
add_library(Shade::filesystem ALIAS shade_filesystem)
shade_configure_module(shade_filesystem)
target_link_libraries(shade_filesystem PUBLIC Shade::foundation)
