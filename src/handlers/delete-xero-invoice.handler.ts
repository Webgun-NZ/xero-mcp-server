import { xeroClient } from "../clients/xero-client.js";
import { XeroClientResponse } from "../types/tool-response.js";
import { formatError } from "../helpers/format-error.js";
import { Invoice } from "xero-node";
import { getClientHeaders } from "../helpers/get-client-headers.js";

const deletableStatuses = [Invoice.StatusEnum.DRAFT, Invoice.StatusEnum.SUBMITTED];

async function getInvoice(invoiceId: string): Promise<Invoice | undefined> {
  await xeroClient.authenticate();

  const response = await xeroClient.accountingApi.getInvoice(
    xeroClient.tenantId,
    invoiceId, // invoiceId
    undefined, // unitdp
    getClientHeaders(), // options
  );

  return response.body.invoices?.[0];
}

async function deleteInvoice(invoiceId: string): Promise<Invoice | undefined> {
  // Xero deletes a draft or submitted invoice by setting its status to DELETED.
  const response = await xeroClient.accountingApi.updateInvoice(
    xeroClient.tenantId,
    invoiceId, // invoiceId
    {
      invoices: [{ status: Invoice.StatusEnum.DELETED }],
    }, // invoices
    undefined, // unitdp
    undefined, // idempotencyKey
    getClientHeaders(), // options
  );

  return response.body.invoices?.[0];
}

/**
 * Delete a draft or submitted invoice in Xero
 */
export async function deleteXeroInvoice(
  invoiceId: string,
): Promise<XeroClientResponse<Invoice>> {
  try {
    const existingInvoice = await getInvoice(invoiceId);
    const invoiceStatus = existingInvoice?.status;

    // Approved invoices must be voided instead, which this tool does not do
    if (!invoiceStatus || !deletableStatuses.includes(invoiceStatus)) {
      return {
        result: null,
        isError: true,
        error: `Cannot delete invoice because it is not a draft or awaiting approval. Current status: ${invoiceStatus}`,
      };
    }

    const deletedInvoice = await deleteInvoice(invoiceId);

    if (!deletedInvoice) {
      throw new Error("Invoice deletion failed.");
    }

    return {
      result: deletedInvoice,
      isError: false,
      error: null,
    };
  } catch (error) {
    return {
      result: null,
      isError: true,
      error: formatError(error),
    };
  }
}
