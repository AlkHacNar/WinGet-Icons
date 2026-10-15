# WinGet-Icons
A set of app icons named with the winget ID as filename for the use with Intune or SCCM.
They are in PNG format and max size is 512x512.
There also are some apps, which aren't in winget but I use, so feel free to add some, or change already available, if you find better ones.

Note: I use this icons with my PowerShell script and wildcards. So there are some apps, which use only 1 icon but have different WinGet IDs like Adobe.Acrobat.Reader.png.

## Requesting an icon
Open an issue with the **Icon request** form: the app's WinGet package ID (`winget search <name>` shows it), and - if you have one - the icon itself (PNG, at most 512x512).
A check answers right away: whether the ID is in WinGet (with a hint when only the capitalisation is off), whether there already is an icon for it, and whether the attached image can be used.
For an app that is not in WinGet, tick **This app is not in WinGet** - its icon then goes to `Non-WinGet/`, named `Vendor.Name` (e.g. `MTG.SmartBridge`).

The App Update Script also opens an issue **Missing icon: &lt;AppID&gt;** by itself when it deploys an app that has no icon here yet.

## Checks
Every icon added to or changed in `WinGet/` or `Non-WinGet/` is checked: in `WinGet/` the file name must be a WinGet package ID or family with WinGet's capitalisation, in `Non-WinGet/` it must follow `Vendor.Name`; every image must be a PNG or JPEG of at most 512x512. Problems open an issue (a pull request is marked failed instead). **Actions > Icon check > Run workflow** checks every icon at once.

## Credits
Thanks to [Aaron Parker](https://github.com/aaronparker/icons) for the idea and some icons I didn't have.

## License

[![License][license-badge]][license]

This repository is licensed with an MIT license; however, the icons themselves remain the property of their respective software vendors.

[license-badge]: https://img.shields.io/github/license/AlkHacNar/WinGet-Icons.svg?style=flat-square
[license]: https://github.com/AlkHacNar/WinGet-Icons/blob/main/LICENSE
