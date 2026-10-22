import { xeroClient } from "../clients/xero-client.js";
import { XeroClientResponse } from "../types/tool-response.js";
import { formatError } from "../helpers/format-error.js";
import { RepeatingInvoice } from "xero-node";
import { getClientHeaders } from "../helpers/get-client-headers.js";

async function deleteRepeatingInvoice(
  repeatingInvoiceId: string,
): Promise<RepeatingInvoice | undefined> {
  await xeroClient.authenticate();

  // Xero deletes a repeating invoice template by setting its status to DELETED.
  // Invoices it has already generated are not affected.
  const response = await xeroClient.accountingApi.updateRepeatingInvoice(
    xeroClient.tenantId,
    repeatingInvoiceId,
    {
      repeatingInvoices: [
        {
          repeatingInvoiceID: repeatingInvoiceId,
          status: RepeatingInvoice.StatusEnum.DELETED,
        },
      ],
    }, // repeatingInvoices
    undefined, //idempotencyKey
    getClientHeaders(),
  );
  return response.body.repeatingInvoices?.[0];
}

/**
 * Delete a repeating invoice template in Xero
 */
export async function deleteXeroRepeatingInvoice(
  repeatingInvoiceId: string,
): Promise<XeroClientResponse<RepeatingInvoice>> {
  try {
    const deletedRepeatingInvoice =
      await deleteRepeatingInvoice(repeatingInvoiceId);

    if (!deletedRepeatingInvoice) {
      throw new Error("Repeating invoice deletion failed.");
    }

    return {
      result: deletedRepeatingInvoice,
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
