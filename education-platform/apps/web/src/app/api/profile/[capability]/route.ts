import { createProfileRouter } from "@/lib/profile/http-boundary";
import { createSupabaseProfileService } from "@/lib/profile/service";

export const dynamic = "force-dynamic";

const handler = createProfileRouter({ createService: createSupabaseProfileService });

export const POST = handler;
export const GET = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
export const OPTIONS = handler;
export const HEAD = handler;
