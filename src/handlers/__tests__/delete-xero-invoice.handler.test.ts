import { describe, it, expect, vi, beforeEach } from "vitest";
import { AxiosError, AxiosHeaders } from "axios";
import { Invoice } from "xero-node";

const { getInvoice, updateInvoice } = vi.hoisted(() => ({
  getInvoice: vi.fn(),
  updateInvoice: vi.fn(),
}));

vi.mock("../../clients/xero-client.js", () => ({
  xeroClient: {
    tenantId: "tenant-1",
    authenticate: vi.fn(),
    accountingApi: { getInvoice, updateInvoice },
  },
}));

vi.mock("../../helpers/get-client-headers.js", () => ({
  getClientHeaders: () => ({ headers: {} }),
}));

import { deleteXeroInvoice } from "../delete-xero-invoice.handler.js";

const invoiceId = "af0cf141-714f-4e84-a777-d974d712e9a7";

const withStatus = (status?: Invoice.StatusEnum) => ({
  body: { invoices: [{ invoiceID: invoiceId, status }] },
});

describe("deleteXeroInvoice", () => {
  beforeEach(() => {
    getInvoice.mockReset();
    updateInvoice.mockReset();
  });

  it.each([Invoice.StatusEnum.DRAFT, Invoice.StatusEnum.SUBMITTED])(
    "deletes a %s invoice by sending only status DELETED",
    async (status) => {
      getInvoice.mockResolvedValue(withStatus(status));
      updateInvoice.mockResolvedValue(withStatus(Invoice.StatusEnum.DELETED));

      const result = await deleteXeroInvoice(invoiceId);

      expect(result.isError).toBe(false);
      expect(String(result.result?.status)).toBe("DELETED");
      expect(updateInvoice).toHaveBeenCalledTimes(1);
      const [, calledId, payload] = updateInvoice.mock.calls[0];
      expect(calledId).toBe(invoiceId);
      expect(payload).toEqual({
        invoices: [{ status: Invoice.StatusEnum.DELETED }],
      });
    },
  );

  it.each([
    Invoice.StatusEnum.AUTHORISED,
    Invoice.StatusEnum.PAID,
    Invoice.StatusEnum.VOIDED,
    Invoice.StatusEnum.DELETED,
    undefined,
  ])("refuses a %s invoice without calling updateInvoice", async (status) => {
    getInvoice.mockResolvedValue(withStatus(status));

    const result = await deleteXeroInvoice(invoiceId);

    expect(result.isError).toBe(true);
    expect(result.error).toContain("not a draft or awaiting approval");
    expect(updateInvoice).not.toHaveBeenCalled();
  });

  it("refuses when the invoice is not found", async () => {
    getInvoice.mockResolvedValue({ body: { invoices: [] } });

    const result = await deleteXeroInvoice(invoiceId);

    expect(result.isError).toBe(true);
    expect(updateInvoice).not.toHaveBeenCalled();
  });

  it("returns a sanitised error when the lookup fails", async () => {
    const headers = new AxiosHeaders({ Authorization: "Bearer secret-token" });
    getInvoice.mockRejectedValue(
      new AxiosError("Request failed", "401", { headers } as never, null, {
        status: 401,
        data: {},
        statusText: "",
        headers: {},
        config: { headers },
      } as never),
    );

    const result = await deleteXeroInvoice(invoiceId);

    expect(result.isError).toBe(true);
    expect(result.error).not.toContain("secret-token");
    expect(updateInvoice).not.toHaveBeenCalled();
  });

  it("returns an error when the update fails", async () => {
    getInvoice.mockResolvedValue(withStatus(Invoice.StatusEnum.DRAFT));
    updateInvoice.mockRejectedValue(new Error("Xero is down"));

    const result = await deleteXeroInvoice(invoiceId);

    expect(result.isError).toBe(true);
    expect(result.error).toContain("Xero is down");
  });
});
