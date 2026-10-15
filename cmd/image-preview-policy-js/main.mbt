///|
extern "js" fn publish_image_policy(policy : (String) -> String) -> Unit =
  #| (policy) => {
  #|   globalThis.MoonLeafImagePreviewPolicy = policy;
  #| }

///|
fn main {
  publish_image_policy(@image_preview.admit_image_preview_json)
}
