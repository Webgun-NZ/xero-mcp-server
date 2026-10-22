import { xeroClient } from "../clients/xero-client.js";
import { XeroClientResponse } from "../types/tool-response.js";
import { formatError } from "../helpers/format-error.js";
import { RepeatingInvoice } from "xero-node";
import { getClientHeaders } from "../helpers/get-client-headers.js";

async function getRepeatingInvoices(
  contactId: string | undefined,
): Promise<RepeatingInvoice[]> {
  await xeroClient.authenticate();

  const response = await xeroClient.accountingApi.getRepeatingInvoices(
    xeroClient.tenantId,
    contactId ? `Contact.ContactID==Guid("${contactId}")` : undefined, // where
    undefined, // order
    getClientHeaders(),
  );
  return response.body.repeatingInvoices ?? [];
}

/**
 * List repeating invoice templates from Xero
 */
export async function listXeroRepeatingInvoices(
  contactId?: string,
): Promise<XeroClientResponse<RepeatingInvoice[]>> {
  try {
    const repeatingInvoices = await getRepeatingInvoices(contactId);

    return {
      result: repeatingInvoices,
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
