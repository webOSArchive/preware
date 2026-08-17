Preware is a webOS on-device homebrew installer.

## Building

The `build.sh` script should do (or at least, suggest) everything you need -- except for signing keys...

Pass `i686` to build for the emulator instead of a device: `./build.sh i686`.

Install the resulting `.ipk` with WebOS Quick Install (WOSQI). The SDK's `palm-install` and
`palm-launch` reject webOS Community Edition devices with "unrecognized device version" --
they do their own host-side parsing of the OS version string and have not been updated for
CE. This is an SDK-side limitation only; `palm-package` is unaffected, so `build.sh` itself
works fine.

## About Keys

The original build server is lost to time, so its impossible to officially sign builds. However, the key files can be found in an original release package. Extract them from that package, and add to the `keys` folder to produce a working build.

## webOS Community Edition 3.1

CE 3.1 reordered the OS version string, which invalidated a couple of long-standing
assumptions:

- `/etc/palm-build-info` reports `PRODUCT_VERSION_STRING=webOS CE 3.1.0`, where stock builds
  report `HP webOS 3.0.5` or `Palm webOS 2.2.4`. The version now trails the *edition* rather
  than the *vendor*, so `control/postinst` no longer looks for a fixed position: it takes the
  last dotted-numeric token on the line. That also survives a digit in the device name
  (`Palm Pre2 webOS 2.2.4`) and a trailing build tag. If it cannot find a version it falls
  back to `unknown` rather than letting an unparsed string reach a feed URL -- the feed
  config is whitespace-delimited, so a value containing a space truncates the URL at the
  space instead of failing visibly.

- `Mojo.Environment.DeviceInfo.platformVersion` is **not** affected. LunaSysMgr already
  strips the `webOS CE ` prefix, so apps see a plain `3.1.0` (verified on a CE 3.1 device).
  Preware compares against that value and never parses the raw string itself, so this is not
  a systemic problem for other Mojo apps.

- The `webos-patches` and `webos-kernels` feeds are published per OS version. Nothing has
  been published for 3.1 yet, so an enabled feed only produces download errors. `postinst`
  ships those two disabled on 3.1 and later, and when the version could not be determined;
  3.0.5 and earlier are unaffected. It writes the `.disabled` name directly instead of using
  the `.conf.new` mechanism, because these were enabled by default in earlier releases and a
  `.new` would find the existing enabled `.conf` on upgrade and keep it enabled. Drop the
  version test in `postinst` once those feeds have content for 3.1.

## Compatibility filtering

Feeds may declare `MinWebOSVersion`, `MaxWebOSVersion` and `DeviceCompatibility`.
`packagesModel#loadPackage` filters on all three as packages are loaded, before they enter
the list:

- A `MinWebOSVersion` newer than the device always hides the package -- it needs APIs the
  device does not have, so there is nothing to opt in to.
- A `MaxWebOSVersion` older than the device, or a device missing from the package's device
  list, hides the package *unless* the "Ignore Compatibility" preference is on. With it on
  the package is shown, and installing or updating it raises an at-your-own-risk prompt.

Both tests live on `packageModel` as `versionIncompatible()` and `deviceIncompatible()`.
They are computed on demand rather than stored as flags so that they survive `infoUpdate()`
merging a package that appears in more than one feed.

Note that these fields are compared numerically and must be plain dotted versions. A
non-numeric component (`3.1.0-CE`) parses to `NaN` and silently compares as equal.

## Feed configuration

`feedsModel.parseConfigLine()` is the single parser for lines in
`/media/cryptofs/apps/etc/ipkg/*.conf`. It splits on any run of whitespace and honours `#`
comments, the way ipkg does. Both the feed loader and the Manage Feeds screen use it, so the
two cannot disagree about a config file -- they previously had separate copies that split on
a single space, where a tab or a double space shifted every field along and produced a feed
whose URL was really the feed name.
