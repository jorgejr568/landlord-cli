export function openMobileAuthorizationCallback(
  url: string,
  assign: (callbackUrl: string) => void = window.location.assign.bind(window.location)
) {
  assign(url);
}
