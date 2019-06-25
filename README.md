# ziguid
GUIDs for zig.

## Usage
```zig
const guid = @import("ziguid");
const GUID = guid.GUID;

const at_comptime = GUID.from("14aacebd-2dfe-4f5c-a475-d1b57b0cb775");

const generate_at_runtime = GUID.v4();
var string_buffer = []u8{0} ** 38;
generate_at_runtime.toString(string_buffer, guid.Format.Braced, guid.Case.Upper);
// "{B10BC49E-E79A-478B-B180-0A7093E2D1BE}"
```

The GUID struct is 16 bytes large and has an identical layout to the GUID struct in the Windows C API.

## License
[GPL-3.0](./LICENSE.md)

If the license is a problem for your use case, please open an issue to discuss.
