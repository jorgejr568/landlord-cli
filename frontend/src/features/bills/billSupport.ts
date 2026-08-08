import type { components } from "../../lib/api/schema";

export type Billing = components["schemas"]["BillingResponse"];
export type Bill = components["schemas"]["BillDetailResponse"];
export type BillCapabilities = components["schemas"]["BillCapabilitiesResponse"];
export type BillLineItemRequest = components["schemas"]["BillLineItemRequest"];
export type BillStatus = components["schemas"]["BillStatus"];
export type Receipt = components["schemas"]["ReceiptResponse"];

export function multipartBodySerializer(body: unknown): BodyInit {
  const form = new FormData();
  if (typeof body !== "object" || body === null) return form;
  Object.entries(body).forEach(([key, value]) => {
    if (value === undefined || value === null) return;
    const values = Array.isArray(value) ? value : [value];
    values.forEach((item) => form.append(key, item instanceof Blob ? item : String(item)));
  });
  return form;
}
