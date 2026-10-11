import { expect, type Locator } from '@playwright/test';

/** Choose through the visible popup, including options rendered in a portal. */
export async function chooseOption(trigger: Locator, choice: string | { label: string }) {
  await trigger.click();
  const popup = trigger.page().getByRole('listbox');
  const option = typeof choice === 'string'
    ? popup.locator(`[role="option"][data-value=${JSON.stringify(choice)}]`)
    : popup.getByRole('option', { name: choice.label, exact: true });
  await option.click();
  await expect(popup).toBeHidden();
}
