# ZMK HID Haptic Tester (macOS only)

This is a command line app that demo to give haptic feedback on mouse cursor state changes. (E.g. hover on hyperlink in browsers, catch the arrows on window corners)

This is proof of concept of sending feedback to hardware HID peripheral via HID-over-GATT on [ZMK Firmware](https://zmk.dev/). Developers are allow to design shield with actuators on baord to reflect haptic feedback by accepting HID Send Report from host, or an internal events such as `zmk_layer_state_changed` being triggered. Actuators would allow be binded in keymap layer setup in behaviors.

The hardware must be powered by [ZMK Firmware](https://zmk.dev/) with cherrypicked [this commit](https://github.com/zmkfirmware/zmk/commit/aae156423fbd7c9e0d805aa81caf8d8c9efc8ce1) and [this commit](https://github.com/zmkfirmware/zmk/commit/ea27e6516b2b5c44df5fa2c2d6f08d49d4b78686) into [ZMK Pull Request #2027](https://github.com/zmkfirmware/zmk/pull/2027).

### This is an EXPERIMENTAL feature and it is not available on official ZMK main branch


## ZMK Config Setup

- Point the west build file to load the zmk source supporting haptic feature in `{zmk-config}/config/west.yaml`

```
manifest:
  remotes:
    - name: badjeff
      url-base: https://github.com/badjeff
  projects:
    - name: zmk
      remote: badjeff
      revision: feat/pointers-move-scroll
      import: app/west.yml
  self:
    path: config
```

- Add device to shield.overlay. `control-gpios` should wired to the base of a transistor that used to switch on and off of a [haptic actuators](https://blog.piezo.com/haptic-actuators-comparing-piezo-erm-lra#benders). Any eccentric rotating mass (ERM) motors, or linear resonant actuators (LRA) should work with a transistor.
```
/ {
	lra0: haptic_generic_lra {
		compatible = "zmk,haptic-generic";
		#haptic-binding-cells = <0>;
		control-gpios = <&gpio0 5 GPIO_ACTIVE_HIGH>;
	};
};
```

- Edit shield.keymap to add `behaviors {...};` above the `keymap {}`, and inject a `output-config-bindings` at the layers which would like to receive haptic feedback on active.

> `force` property in `zmk,behavior-output-config` is under development, it will be used to define formation of feedback to emulate different kind of sense of touch.

```
/ {
        behaviors {
                lar0_hid: behavior_output_config_lar0_transport {
                        compatible = "zmk,behavior-output-config";
                        #output-config-binding-cells = <0>; 
                        device = <&lra0>;
                        source = "transport";
                        // force = <0>;

                        /* clone this node with below alternative 'source' */
                        /* to monitor other internal event */
                        // source = "layer-state-change";
                        // source = "position-state-change";
                        // source = "keycode-state-change";
                        // source = "mouse-button-state-change";
                };

        };

        keymap {
                compatible = "zmk,keymap";
                default_layer {
                        bindings = <
    &kp Q .... .... .... ...
    &kp A .... .... .... ...
    &kp Z .... .... .... ...
                        >;

                        /* START -- Inject here */
                        /*   Note: multi-behaviors is allowing */
                        /*   <&behaviors1 &behaviors1 &behaviors1> */

                        output-config-bindings = <&lar0_hid>;

                        /* END -- Inject here */
                };
       };

};
```

- Add `CONFIG_ZMK_HAPTIC=y` to your shield.conf


## Host Setup

- Pull & Build
```
git clone https://github.com/badjeff/zmk-haptic-tester-macos.git
cd zmk-haptic-tester-macos
git submodule update --recursive
make
```

- Run `./haptic-tester --list`
- Get `serial_number` of device to connect to
- Open 'System Settings -> Security' and  grant the permissoin to Termianl.app
- Execute with sudo and the ZMK device serial number
```
sudo ./haptic-tester --serial XXXXXXXXXX --start-haptic-cursor
```
- Hover the cursor on any hyperlink in browser


## Credits

This app is just a mixture of below repositories

* [libusb/hidapi](https://github.com/libusb/hidapi)
* [todbot/hidapitester](https://github.com/todbot/hidapitester)
* [sh1ura/haptic-feedback-mouse](https://github.com/sh1ura/haptic-feedback-mouse.git)

## License

GPL v3
