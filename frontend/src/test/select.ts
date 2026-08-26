import { screen } from "@testing-library/react";

interface ClickUser {
  click: (element: Element) => Promise<void>;
}

export async function chooseSelectOption(
  user: ClickUser,
  trigger: HTMLElement,
  optionName: string
): Promise<void> {
  await user.click(trigger);
  await user.click(await screen.findByRole("option", { name: optionName }));
}
