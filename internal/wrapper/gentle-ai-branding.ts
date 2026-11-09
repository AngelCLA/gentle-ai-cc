// Static, local-only decoration. The built-in Command Code banner is unchanged.
// Plain JavaScript syntax keeps this factory dependency-free in the loose mod.
export default function (cmd) {
  cmd.ui.widget({
    placement: "above-editor",
    render: () => ["@}-'-,—  Gentle AI"],
  });
}
