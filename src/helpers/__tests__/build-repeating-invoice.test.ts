import { describe, it, expect } from "vitest";
import {
  buildRepeatingInvoice,
  RepeatingInvoiceInput,
} from "../build-repeating-invoice.js";

const baseInput: RepeatingInvoiceInput = {
  contactId: "9cbef222-8034-4072-bea3-4a8e5daf159e",
  type: "ACCREC",
  lineItems: [
    {
      description: "Monthly services",
      quantity: 1,
      unitAmount: 1250,
      accountCode: "200",
      taxType: "OUTPUT2",
    },
  ],
  period: 1,
  unit: "MONTHLY",
  startDate: "2026-11-01",
  dueDate: 3,
  dueDateType: "DAYSAFTERBILLDATE",
};

describe("buildRepeatingInvoice", () => {
  it("builds a monthly draft by default", () => {
    const result = buildRepeatingInvoice(baseInput);
    expect(String(result.type)).toBe("ACCREC");
    expect(String(result.status)).toBe("DRAFT");
    expect(result.contact).toEqual({ contactID: baseInput.contactId });
    expect(result.schedule?.period).toBe(1);
    expect(String(result.schedule?.unit)).toBe("MONTHLY");
    expect(result.schedule?.dueDate).toBe(3);
    expect(String(result.schedule?.dueDateType)).toBe("DAYSAFTERBILLDATE");
    expect(result.schedule?.startDate).toBe("2026-11-01");
    expect(result.schedule?.endDate).toBeUndefined();
    expect(result.approvedForSending).toBeUndefined();
  });

  it("sets email flags for an approved sales invoice", () => {
    const result = buildRepeatingInvoice({
      ...baseInput,
      status: "AUTHORISED",
      approvedForSending: true,
      lineAmountTypes: "Exclusive",
    });
    expect(String(result.status)).toBe("AUTHORISED");
    expect(result.approvedForSending).toBe(true);
    expect(result.includePDF).toBe(true);
    expect(result.sendCopy).toBe(false);
    expect(result.markAsSent).toBe(false);
    expect(String(result.lineAmountTypes)).toBe("Exclusive");
  });

  it("refuses approvedForSending on a draft", () => {
    expect(() =>
      buildRepeatingInvoice({ ...baseInput, approvedForSending: true }),
    ).toThrow("approvedForSending requires status AUTHORISED");
  });

  it("refuses approvedForSending on a bill", () => {
    expect(() =>
      buildRepeatingInvoice({
        ...baseInput,
        type: "ACCPAY",
        status: "AUTHORISED",
        approvedForSending: true,
      }),
    ).toThrow("approvedForSending is only valid for ACCREC invoices");
  });

  it("refuses email options without approvedForSending", () => {
    expect(() =>
      buildRepeatingInvoice({ ...baseInput, sendCopy: true }),
    ).toThrow("require approvedForSending");
  });

  it("refuses badly formatted or reversed dates", () => {
    expect(() =>
      buildRepeatingInvoice({ ...baseInput, startDate: "1/11/2026" }),
    ).toThrow("startDate must be in YYYY-MM-DD format");
    expect(() =>
      buildRepeatingInvoice({ ...baseInput, endDate: "2026-10-01" }),
    ).toThrow("endDate must be on or after startDate");
  });

  it("refuses an invalid period, due date or empty line items", () => {
    expect(() => buildRepeatingInvoice({ ...baseInput, period: 0 })).toThrow(
      "period must be a whole number of 1 or more",
    );
    expect(() => buildRepeatingInvoice({ ...baseInput, dueDate: -1 })).toThrow(
      "dueDate must be a whole number of 0 or more",
    );
    expect(() => buildRepeatingInvoice({ ...baseInput, lineItems: [] })).toThrow(
      "At least one line item is required",
    );
  });
});
