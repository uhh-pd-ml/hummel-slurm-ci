-- Emulation of the Hummel-2 "rrz5" job-submit plugin.  Only rules that were
-- observed with `sbatch --test-only` on the real login nodes are reproduced:
--   * "no --mem/memory parameter allowed"
--   * "multi-node jobs must be --exclusive"
--   * "logfile is not writable in: <dir>" (/home and /usw are read-only in
--     batch jobs, so the log/working directory must live elsewhere)

local RO_PREFIXES = { "/home/", "/usw/" }

local function fail(msg)
   slurm.log_user("RRZ check failed: " .. msg)
   return slurm.ERROR
end

local function read_only(path)
   for _, prefix in ipairs(RO_PREFIXES) do
      if string.sub(path, 1, #prefix) == prefix then
         return true
      end
   end
   return false
end

function slurm_job_submit(job_desc, part_list, submit_uid)
   -- memory: neither --mem nor --mem-per-cpu (the latter carries a flag bit)
   if job_desc.pn_min_memory ~= nil and job_desc.pn_min_memory ~= slurm.NO_VAL64 then
      return fail("no --mem/memory parameter allowed")
   end

   -- multi-node jobs must be exclusive (shared == 0 means --exclusive)
   if job_desc.min_nodes ~= nil and job_desc.min_nodes ~= slurm.NO_VAL
      and job_desc.min_nodes > 1 and job_desc.shared ~= 0 then
      return fail("multi-node jobs must be --exclusive")
   end

   -- log destination must be writable on compute nodes
   local out = job_desc.std_out
   local dir
   if out ~= nil and out ~= "" then
      dir = string.match(out, "^(.*)/[^/]*$") or job_desc.work_dir
   else
      dir = job_desc.work_dir
   end
   if dir ~= nil and dir ~= "" and read_only(dir .. "/") then
      slurm.log_user("RRZ check failed:")
      slurm.log_user("   logfile is not writable in: " .. dir)
      slurm.log_user("   Use a writable working directory or specify --output.")
      return slurm.ERROR
   end

   return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
   return slurm.SUCCESS
end
