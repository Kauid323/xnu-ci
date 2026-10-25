# Porting worksheet

Hunks of `hackios-8796.patch` that do not apply to `xnu-xnu-8020.140.41` even with three lines of fuzz.
**10 of 185 hunks do not apply.**

## bsd/kern/kern_exec.c

```diff
@@ -3105,12 +3171,6 @@ spawn_validate_persona(struct _posix_spawn_persona_info *px_persona)
 	}
 
 	persona = persona_lookup(px_persona->pspi_id);
-	if (!persona) {
-		error = ESRCH;
-		goto out;
-	}
-
-out:
 	if (persona) {
 		persona_put(persona);
 	}
```

target bsd/kern/kern_exec.c around line 3105:

```
 3094| 		struct vnode_attr va;
 3095| 		struct vnode_attr origva;
 3096| 	} *__spawn_data;
 3097| 
 3098| 	/*
 3099| 	 * Allocate a big chunk for locals instead of using stack since these
 3100| 	 * structures are pretty big.
 3101| 	 */
 3102| 	__spawn_data = kalloc_type(typeof(*__spawn_data), Z_WAITOK | Z_ZERO);
 3103| 	if (__spawn_data == NULL) {
 3104| 		error = ENOMEM;
 3105| 		goto bad;
 3106| 	}
 3107| 	imgp = &__spawn_data->imgp;
 3108| 	vap = &__spawn_data->va;
 3109| 	origvap = &__spawn_data->origva;
 3110| 
 3111| 	/* Initialize the common data in the image_params structure */
 3112| 	imgp->ip_user_fname = uap->path;
 3113| 	imgp->ip_user_argv = uap->argv;
 3114| 	imgp->ip_user_envv = uap->envp;
 3115| 	imgp->ip_vattr = vap;
 3116| 	imgp->ip_origvattr = origvap;
 3117| 	imgp->ip_vfs_context = &context;
 3118| 	imgp->ip_flags = (is_64 ? IMGPF_WAS_64BIT_ADDR : IMGPF_NONE);
 3119| 	imgp->ip_seg = (is_64 ? UIO_USERSPACE64 : UIO_USERSPACE32);
 3120| 	imgp->ip_mac_return = 0;
 3121| 	imgp->ip_px_persona = NULL;
 3122| 	imgp->ip_px_pcred_info = NULL;
 3123| 	imgp->ip_cs_error = OS_REASON_NULL;
 3124| 	imgp->ip_simulator_binary = IMGPF_SB_DEFAULT;
 3125| 	imgp->ip_subsystem_root_path = NULL;
```

## bsd/vm/vm_unix.c

```diff
@@ -2538,7 +2538,19 @@ after_root_check:
 #define PREBOOT_CRYPTEX_PATH "/private/preboot/Cryptexes"
 #endif
 			error = vnode_lookup(PREBOOT_CRYPTEX_PATH, 0, &preboot_vp, vfs_context_current());
-			if (error || srfmp->vp->v_mount != preboot_vp->v_mount) {
+			/*
+			 * (redwood) Or a volume of its own mounted on a directory right inside it: iOS
+			 * grafts each cryptex image into the Preboot volume (graftdmg), so its files are
+			 * that volume's; this port mounts the image there as it is (bsd/miscfs/apfs), a
+			 * mount of its own whose covered directory is Preboot's Cryptexes/<name>.
+			 */
+			if (error == 0 && srfmp->vp->v_mount != preboot_vp->v_mount &&
+			    srfmp->vp->v_mount != NULL && srfmp->vp->v_mount->mnt_vnodecovered != NULLVP &&
+			    srfmp->vp->v_mount->mnt_vnodecovered->v_mount == preboot_vp->v_mount &&
+			    srfmp->vp->v_mount->mnt_vnodecovered->v_parent == preboot_vp) {
+				(void)vnode_put(preboot_vp);
+				preboot_vp = NULL;
+			} else if (error || srfmp->vp->v_mount != preboot_vp->v_mount) {
 				SHARED_REGION_TRACE_ERROR(
 					("shared_region: %p [%d(%s)] map(%p:'%s'): "
 					"not on process' root volume nor preboot volume\n",
```

target bsd/vm/vm_unix.c around line 2538:

```
 2527| 					srfmp->mappings[i].sms_init_prot));
 2528| 				error = EINVAL;
 2529| 				goto done;
 2530| 			}
 2531| 		}
 2532| 	}
 2533| done:
 2534| 	if (error != 0) {
 2535| 		shared_region_map_and_slide_cleanup(p, files_count, *sr_file_mappings, shared_region, *scdir_vp);
 2536| 		*sr_file_mappings = NULL;
 2537| 		*shared_region_ptr = NULL;
 2538| 		*scdir_vp = NULL;
 2539| 	}
 2540| 	return error;
 2541| }
 2542| 
 2543| /*
 2544|  * shared_region_map_np()
 2545|  *
 2546|  * This system call is intended for dyld.
 2547|  *
 2548|  * dyld uses this to map a shared cache file into a shared region.
 2549|  * This is usually done only the first time a shared cache is needed.
 2550|  * Subsequent processes will just use the populated shared region without
 2551|  * requiring any further setup.
 2552|  */
 2553| static int
 2554| _shared_region_map_and_slide(
 2555| 	struct proc                         *p,
 2556| 	uint32_t                            files_count,
 2557| 	struct shared_file_np               *files,
 2558| 	uint32_t                            mappings_count,
```

## config/MASTER.arm64.bcm2837

```diff
@@ -16,15 +16,15 @@
 #  Standard Apple OS Configurations:
 #  -------- ----- -- ---------------
 #
-#  KERNEL_BASE =    [ arm64 config_pmap_ppl xsmall msgb_small config_embedded config_requires_u32_munging ARM_EXTRAS_BASE ]
+#  KERNEL_BASE =    [ arm64 config_pmap_ppl xsmall msgb_small config_embedded config_requires_u32_munging nos_arm_pmap nos_arm_asm ]
 #  KERNEL_RELEASE = [ KERNEL_BASE ]
 #  KERNEL_DEV =     [ KERNEL_BASE development mach_assert config_xnupost proc_ref_debug ]
 #  KERNEL_DEBUG =   [ KERNEL_BASE debug mach_assert config_xnupost config_waitq_stats config_workloop_debug ]
 #  BSD_BASE =       [ mach_bsd psynch config_proc_uuid_policy config_personas ]
 #  BSD_RELEASE =    [ BSD_BASE no_printf_str no_kprintf_str secure_kernel ]
-#  BSD_DEV =        [ BSD_BASE config_netboot config_imageboot config_coredump pgo config_vnguard ]
-#  BSD_DEBUG =      [ BSD_BASE config_netboot config_imageboot config_coredump pgo config_vnguard ]
-#  FILESYS_BASE =   [ devfs fifo fs_compression config_protect config_mnt_rootsnap config_fse routefs namedstreams bindfs]
+#  BSD_DEV =        [ BSD_BASE config_netboot config_imageboot config_coredump config_vnguard ]
+#  BSD_DEBUG =      [ BSD_BASE config_netboot config_imageboot config_coredump config_vnguard ]
+#  FILESYS_BASE =   [ devfs fifo fs_compression config_protect config_mnt_rootsnap config_fse routefs namedstreams bindfs mockfs ramfs apfs ]
 #  FILESYS_RELEASE= [ FILESYS_BASE ]
 #  FILESYS_DEV =    [ FILESYS_BASE config_union_mounts fdesc ]
 #  FILESYS_DEBUG =  [ FILESYS_BASE config_union_mounts fdesc ]
```

target config/MASTER.arm64.bcm2837 around line 16:

```
    5| #
    6| # All rights reserved.  The CMU software License Agreement
    7| # specifies the terms and conditions for use and redistribution.
    8| #
    9| ######################################################################
   10| #
   11| #  Master Apple configuration file (see the master machine independent
   12| #  configuration file for a description of the file format).
   13| #
   14| ######################################################################
   15| #
   16| #  Standard Apple OS Configurations:
   17| #  -------- ----- -- ---------------
   18| #
   19| #  ARM_EXTRAS_BASE = [ nos_arm_pmap nos_arm_asm ]
   20| #  KERNEL_BASE =    [ arm64 xsmall msgb_small config_embedded config_requires_u32_munging ARM_EXTRAS_BASE ]
   21| #  KERNEL_RELEASE = [ KERNEL_BASE ]
   22| #  KERNEL_DEV =     [ KERNEL_BASE development mach_assert config_xnupost proc_ref_debug ]
   23| #  KERNEL_DEBUG =   [ KERNEL_BASE debug mach_assert config_xnupost config_waitq_stats config_workloop_debug ]
   24| #  BSD_BASE =       [ mach_bsd config_workqueue psynch config_proc_uuid_policy config_personas ]
   25| #  BSD_RELEASE =    [ BSD_BASE no_printf_str no_kprintf_str secure_kernel ]
   26| #  BSD_DEV =        [ BSD_BASE config_netboot config_imageboot config_coredump pgo config_vnguard ]
   27| #  BSD_DEBUG =      [ BSD_BASE config_netboot config_imageboot config_coredump pgo config_vnguard ]
   28| #  FILESYS_BASE =   [ devfs fifo fs_compression config_protect config_mnt_rootsnap config_fse routefs namedstreams bindfs]
   29| #  FILESYS_RELEASE= [ FILESYS_BASE ]
   30| #  FILESYS_DEV =    [ FILESYS_BASE config_union_mounts fdesc ]
   31| #  FILESYS_DEBUG =  [ FILESYS_BASE config_union_mounts fdesc ]
   32| #  NFS_DEV =        [ nfsclient nfsserver config_nfs_gss ]
   33| #  NFS_RELEASE =    [ nfsclient ]
   34| #  NFS_DEBUG =      [ nfsclient config_nfs_gss ]
   35| #  SKYWALK_BASE =   [ skywalk config_nexus_user_pipe config_nexus_kernel_pipe config_nexus_monitor config_nexus_flowswitch config_nexus_netif ]
   36| #  SKYWALK_RELEASE = [ SKYWALK_BASE ]
```

## config/MASTER.arm64.bcm2837

```diff
@@ -50,8 +50,8 @@
 #  LIBKERN_DEBUG =  [ LIBKERN_BASE iotracking ]
 #  PERF_DBG_BASE =  [ mach_kdp config_serial_kdp kperf kpc ]
 #  PERF_DBG_RELEASE=[ PERF_DBG_BASE ist_kdebug ]
-#  PERF_DBG_DEV =   [ PERF_DBG_BASE config_dtrace zleaks kdp_interactive_debugging alternate_debugger sched_hygiene_debug config_iotrace]
-#  PERF_DBG_DEBUG = [ PERF_DBG_BASE config_dtrace zleaks kdp_interactive_debugging alternate_debugger sched_hygiene_debug config_iotrace]
+#  PERF_DBG_DEV =   [ PERF_DBG_BASE config_dtrace zleaks kdp_interactive_debugging alternate_debugger config_iotrace]
+#  PERF_DBG_DEBUG = [ PERF_DBG_BASE config_dtrace zleaks kdp_interactive_debugging alternate_debugger config_iotrace]
 #  MACH_BASE =      [ mach config_ecc_logging vc_progress_white importance_inheritance config_atm config_coalitions config_iosched config_library_validation config_sysdiagnose config_telemetry config_mach_bridge_recv_time config_quiesce_counter config_service_port_info ]
 #  MACH_RELEASE =   [ MACH_BASE config_skip_precise_user_kernel_time debugger_for_zone_info ]
 #  MACH_DEV =       [ MACH_BASE config_io_accounting importance_trace ]
```

target config/MASTER.arm64.bcm2837 around line 50:

```
   39| #  NETWORKING =     [ inet bpfilter if_bridge traffic_mgt dummynet ah_all_crypto if_fake ]
   40| #  NETWORKING_RELEASE = [ NETWORKING ]
   41| #  NETWORKING_DEV = [ NETWORKING_RELEASE packet_mangler if_headless ]
   42| #  NETWORKING_DEBUG = [ NETWORKING_DEV ]
   43| #  VPN =            [ ipsec flow_divert necp content_filter ]
   44| #  PF =             [ pf ]
   45| #  MULTIPATH =      [ multipath mptcp ]
   46| #  IOKIT_BASE =     [ iokit iokitcpp no_kextd no_kernel_hid config_sleep ]
   47| #  IOKIT_RELEASE =  [ IOKIT_BASE ]
   48| #  IOKIT_DEV =      [ IOKIT_BASE iokitstats iotracking ]
   49| #  IOKIT_DEBUG =    [ IOKIT_BASE iokitstats iotracking]
   50| #  LIBKERN_BASE =   [ libkerncpp config_blocks config_kec_fips zlib crypto_sha2 ]
   51| #  LIBKERN_RELEASE =[ LIBKERN_BASE ]
   52| #  LIBKERN_DEV =    [ LIBKERN_BASE iotracking ]
   53| #  LIBKERN_DEBUG =  [ LIBKERN_BASE iotracking ]
   54| #  PERF_DBG_BASE =  [ mach_kdp config_serial_kdp kperf kpc ]
   55| #  PERF_DBG_RELEASE=[ PERF_DBG_BASE ist_kdebug ]
   56| #  PERF_DBG_DEV =   [ PERF_DBG_BASE config_dtrace zleaks kdp_interactive_debugging alternate_debugger interrupt_masked_debug sched_preemption_disable_debug ]
   57| #  PERF_DBG_DEBUG = [ PERF_DBG_BASE config_dtrace zleaks kdp_interactive_debugging alternate_debugger interrupt_masked_debug sched_preemption_disable_debug ]
   58| #  MACH_BASE =      [ mach slidable config_ecc_logging vc_progress_white mdebug ipc_debug ipc_lockfree_space importance_inheritance config_atm config_coalitions config_iosched config_library_validation config_sysdiagnose config_telemetry config_mach_bridge_recv_time config_quiesce_counter config_service_port_info ]
   59| #  MACH_RELEASE =   [ MACH_BASE config_skip_precise_user_kernel_time debugger_for_zone_info ]
   60| #  MACH_DEV =       [ MACH_BASE task_zone_info config_io_accounting importance_trace ]
   61| #  MACH_DEBUG =     [ MACH_BASE task_zone_info config_io_accounting importance_trace importance_debug ]
   62| #  SCHED_BASE =     [ config_sched_traditional config_sched_multiq config_sched_deferred_ast config_clutch config_taskwatch ]
   63| #  SCHED_RELEASE =  [ SCHED_BASE ]
   64| #  SCHED_DEV =      [ SCHED_BASE ]
   65| #  SCHED_DEBUG =    [ SCHED_BASE config_sched_grrr config_sched_proto ]
   66| #  VM_BASE =        [ vm_pressure_events jetsam freeze memorystatus config_code_decryption phantom_cache config_secluded_memory config_background_queue config_cs_validation_bitmap ]
   67| #  VM_RELEASE =     [ VM_BASE ]
   68| #  VM_DEV =         [ VM_BASE dynamic_codesigning ubsan_minimal pgzalloc ]
   69| #  VM_DEBUG =       [ VM_BASE dynamic_codesigning ubsan_minimal pgzalloc ]
   70| #  VM_KASAN =       [ VM_BASE dynamic_codesigning config_kasan config_ubsan config_kcov config_ksancov ]
```

## makedefs/MakeInc.cmd

```diff
@@ -100,12 +100,12 @@ ifeq ($(VERBOSE),YES)
 	_v =
 	_vstdout =
 	_vstderr =
-	XCRUN = /usr/bin/xcrun -verbose
+	XCRUN = xcrun -verbose
 else
 	_v = @
 	_vstdout = > /dev/null
 	_vstderr = 2> /dev/null
-	XCRUN = /usr/bin/xcrun
+	XCRUN = xcrun
 endif
 
 VERBOSE_GENERATED_MAKE_FRAGMENTS = NO
```

target makedefs/MakeInc.cmd around line 100:

```
   89| 
   90| # Host-side linking operations.
   91| LOG_GENASSYM = $(call _LOG_HOST_LINK,GENASSYM)
   92| LOG_GENERATE= $(call _LOG_HOST_LINK,GENERATE)
   93| LOG_CTFCONVERT = $(call _LOG_HOST_LINK,CTFCONVERT)
   94| LOG_CTFMERGE = $(call _LOG_HOST_LINK,CTFMERGE)
   95| LOG_CTFINSERT = $(call _LOG_HOST_LINK,CTFINSERT)
   96| LOG_DSYMUTIL = $(call _LOG_HOST_LINK,DSYMUTIL)
   97| LOG_SUPPORTED_KPI = $(call _LOG_HOST_LINK,SUPPORTED_KPI)
   98| 
   99| ifeq ($(VERBOSE),YES)
  100| 	_v =
  101| 	_vstdout =
  102| 	_vstderr =
  103| 	XCRUN = /usr/bin/xcrun -verbose
  104| else
  105| 	_v = @
  106| 	_vstdout = > /dev/null
  107| 	_vstderr = 2&> /dev/null
  108| 	XCRUN = /usr/bin/xcrun
  109| endif
  110| 
  111| VERBOSE_GENERATED_MAKE_FRAGMENTS = NO
  112| 
  113| #
  114| # Defaults
  115| #
  116| 
  117| SDKROOT ?= macosx
  118| HOST_SDKROOT ?= macosx
  119| 
  120| # SDKROOT may be passed as a shorthand like "iphoneos.internal". We
```

## osfmk/arm/pmap/pmap.c — **file missing in the target tree**

## osfmk/arm/pmap/pmap.h — **file missing in the target tree**

## osfmk/conf/files.arm64

```diff
@@ -25,8 +25,8 @@ osfmk/arm64/WKdmCompress_4k.s	standard
 osfmk/arm64/WKdmData.s		standard
 osfmk/arm64/lz4_decode_arm64.s  standard
 osfmk/arm64/lz4_encode_arm64.s  standard
-osfmk/arm64/amcc_rorgn_ppl.c optional nos_arm_asm config_pmap_ppl
-osfmk/arm64/amcc_rorgn_common.c optional nos_arm_asm
+#osfmk/arm64/amcc_rorgn_ppl.c optional nos_arm_asm config_pmap_ppl
+#osfmk/arm64/amcc_rorgn_common.c optional nos_arm_asm
 osfmk/arm64/bcopy.s standard
 osfmk/arm64/bzero.s standard
 osfmk/arm/caches.c		standard
```

target osfmk/conf/files.arm64 around line 25:

```
   14| osfmk/arm/pmap/pmap_misc.c		optional nos_arm_pmap
   15| osfmk/arm/pmap/pmap_ppl_interface.c	optional nos_arm_pmap
   16| 
   17| osfmk/arm64/bsd_arm64.c		optional mach_bsd
   18| osfmk/arm/machdep_call.c	optional mach_bsd
   19| 
   20| osfmk/arm64/WKdmDecompress_16k.s	standard
   21| osfmk/arm64/WKdmCompress_16k.s		standard
   22| osfmk/arm64/WKdmDecompress_4k.s	standard
   23| osfmk/arm64/WKdmCompress_4k.s	standard
   24| osfmk/arm64/WKdmData.s		standard
   25| osfmk/arm64/lz4_decode_arm64.s  standard
   26| osfmk/arm64/lz4_encode_arm64.s  standard
   27| osfmk/arm64/amcc_rorgn.c optional nos_arm_asm
   28| osfmk/arm64/bcopy.s standard
   29| osfmk/arm64/bzero.s standard
   30| osfmk/arm/caches.c		standard
   31| osfmk/arm64/caches_asm.s		optional nos_arm_asm
   32| osfmk/arm64/copyio.c	standard
   33| osfmk/arm64/cpu.c		standard
   34| osfmk/arm/cpu_common.c		standard
   35| osfmk/arm/cpuid.c   standard
   36| osfmk/arm/data.s	standard
   37| osfmk/arm64/dbgwrap.c		standard
   38| osfmk/arm/arm_timer.c		standard
   39| osfmk/arm/arm_init.c	standard
   40| osfmk/arm64/arm_vm_init.c	standard
   41| osfmk/arm/io_map.c		standard
   42| osfmk/arm64/loose_ends.c	standard
   43| osfmk/arm/locks_arm.c	standard
   44| osfmk/arm64/locore.s	optional nos_arm_asm
   45| osfmk/arm64/gxf_exceptions.s	optional nos_arm_asm
```

## osfmk/kern/kalloc.h

```diff
@@ -821,12 +821,16 @@ __options_decl(kt_granule_t, uint32_t, {
  * @param ptr           the pointer whose type needs to be checked.
  * @param type          the type which the pointer will be checked against.
  */
+#if XNU_NO_TYPE_BUILTINS
+#define KALLOC_TYPE_IS_COMPATIBLE_PTR(ptr, type)  (1)
+#else
 #define KALLOC_TYPE_IS_COMPATIBLE_PTR(ptr, type)                   \
 	_Pragma("clang diagnostic push")                               \
 	_Pragma("clang diagnostic ignored \"-Wvoid-ptr-dereference\"") \
 	(__builtin_xnu_types_compatible(__typeof__(*(ptr)), type) ||   \
 	    __builtin_xnu_types_compatible(__typeof__(*(ptr)), void))  \
 	_Pragma("clang diagnostic pop")
+#endif /* XNU_NO_TYPE_BUILTINS */
 
 #define KALLOC_TYPE_ASSERT_COMPATIBLE_POINTER(ptr, type) \
 	_Static_assert(KALLOC_TYPE_IS_COMPATIBLE_PTR(ptr, type), \
```

target osfmk/kern/kalloc.h around line 821:

```
  810| 	    __builtin_xnu_types_compatible(__typeof__(*ptr), void))    \
  811| 	_Pragma("clang diagnostic pop")
  812| 
  813| #define KALLOC_TYPE_ASSERT_COMPATIBLE_POINTER(ptr, type)                  \
  814| 	_Static_assert(KALLOC_TYPE_IS_COMPATIBLE_PTR(ptr, type),           \
  815| 	    "Pointer type is not compatible with specified type")
  816| 
  817| #pragma mark implementation details
  818| 
  819| 
  820| static inline void *
  821| kt_mangle_var_view(kalloc_type_var_view_t kt_view)
  822| {
  823| 	return (void *)((uintptr_t)kt_view | 1ul);
  824| }
  825| 
  826| static inline kalloc_type_var_view_t
  827| kt_demangle_var_view(void *ptr)
  828| {
  829| 	return (kalloc_type_var_view_t)((uintptr_t)ptr & ~1ul);
  830| }
  831| 
  832| #define kt_is_var_view(ptr)  ((uintptr_t)(ptr) & 1)
  833| 
  834| static inline vm_size_t
  835| kt_size(vm_size_t s1, vm_size_t s2, vm_size_t c2)
  836| {
  837| 	/* kalloc_large() will reject this size before even asking the VM  */
  838| 	const vm_size_t limit = 1ull << (8 * sizeof(vm_size_t) - 1);
  839| 
  840| 	if (os_mul_and_add_overflow(s2, c2, s1, &s1) || (s1 & limit)) {
  841| 		return limit;
```

## osfmk/kern/percpu.h

```diff
@@ -236,15 +236,22 @@ extern vm_offset_t other_percpu_base(int cpu_number);
  * @param it            the name of the iterator
  * @param name          the per-CPU variable name
  */
+/*
+ * (redwood) All of the arithmetic is on integers here. As Apple wrote it, the end was a pointer
+ * computed from the start, and a compiler may then take "start <= start + n" for "n >= 0":
+ * with one processor start is VM_MAX_KERNEL_ADDRESS and end is 0, n looks positive, and the
+ * loop that must not run at all runs once on memory that does not exist (clang 18+ does this;
+ * the panic was in mbuf_mtypes_sync(), the first time a daemon asked for the mbuf statistics).
+ */
 #define percpu_foreach_secondary(it, name) \
 	for (__PERCPU_TYPE(name) it, \
-	    __base_ ## it = (typeof(it))__unsafe_forge_bidi_indexable(void *, percpu_base.start, percpu_base.end - percpu_base.start), \
-	    __end_ ## it = (typeof(it))((caddr_t)__base_ ## it  + percpu_base.end - percpu_base.start); \
+	    __base_ ## it = (typeof(it))percpu_base.start, \
+	    __end_ ## it = (typeof(it))percpu_base.end; \
         \
-	    (it = (typeof(it))((caddr_t)__base_ ## it + __PERCPU_ADDR(name)), \
-	    __base_ ## it <= __end_ ## it); \
+	    (it = (typeof(it))((vm_address_t)__base_ ## it + __PERCPU_ADDR(name)), \
+	    (vm_address_t)__base_ ## it <= (vm_address_t)__end_ ## it); \
         \
-	    __base_ ## it = (typeof(it))((caddr_t)__base_ ## it + percpu_section_size()))
+	    __base_ ## it = (typeof(it))((vm_address_t)__base_ ## it + percpu_section_size()))
 
 #pragma mark - implementation details
 
```

target osfmk/kern/percpu.h around line 236:

```
  225|  * @param it            the name of the iterator
  226|  * @param name          the per-CPU variable name
  227|  */
  228| #define percpu_foreach_secondary(it, name) \
  229| 	for (__PERCPU_TYPE(name) it, \
  230| 	    __base_ ## it = (typeof(it))percpu_base.start, \
  231| 	    __end_ ## it = (typeof(it))percpu_base.end; \
  232|         \
  233| 	    (it = (typeof(it))(__PERCPU_ADDR(name) + (vm_address_t)__base_ ## it), \
  234| 	    __base_ ## it <= __end_ ## it); \
  235|         \
  236| 	    __base_ ## it = (typeof(it))((vm_address_t)__base_ ## it + percpu_section_size()))
  237| 
  238| #pragma mark - implementation details
  239| 
  240| /*
  241|  * Below this point are implementation details that should not be used directly,
  242|  * except by the macros above, or architecture specific code.
  243|  */
  244| 
  245| #define __percpu                        __attribute__((section("__DATA, __percpu")))
  246| #define __PERCPU_NAME(name)             percpu_slot_ ## name
  247| #define __PERCPU_ADDR(name)             ((vm_offset_t)&__PERCPU_NAME(name))
  248| #define __PERCPU_TYPE(name)             typeof(&__PERCPU_NAME(name))
  249| #define __PERCPU_CAST(name, expr)       ((__PERCPU_TYPE(name))(expr))
  250| 
  251| /*
  252|  * Note for implementors:
  253|  *
  254|  * A `base` represents a pointer in the percpu allocation offset by
  255|  * `percpu_section_start()` so that PERCPU_GET() is a single addition.
  256|  *
```


---

## 两个"文件不存在"的其实是**路径变了**（最好先处理）

`osfmk/arm/pmap/pmap.c` / `pmap.h` 在 8796 里是一个目录里的文件，在 **8020 里是
`osfmk/arm/pmap.c` / `osfmk/arm/pmap.h`**（往上一级，单文件 13358 行）。

所以先把补丁里这两条路径改掉，再谈内容：

```
sed -i 's|osfmk/arm/pmap/pmap\.c|osfmk/arm/pmap.c|g; s|osfmk/arm/pmap/pmap\.h|osfmk/arm/pmap.h|g' patches/*.patch
```

那两个 hunk 的内容本身很小，而且**对 cactus 都重要**：

| hunk | 内容 | 为什么重要 |
|---|---|---|
| `pmap_sync_page_attributes_phys` | `flush_dcache((vm_offset_t) pp << PAGE_SHIFT, …)` → 先转 64 位再移位 | ppnum 32 位、内存超过 4 GB 时原写法会截断；cactus 的 DRAM 一直到 `0xFFFFF000` |
| `pmap_cs_lockdown_pages` / `unlockdown` | `#else` 分支里不再调 `pmap_ppl_*`，改成空实现 | 这颗 SoC 没有 PPL，XNU_MONITOR 关着 |
| 声明 `pmap_phys_write_disable` | 一行前置声明 | 平台层要用 |
| `pmap_page_protect` 的 panic 格式串 | 去掉 `ptep_get_iommu(pte_p)` | 编译期就要 |

## 其余 8 个 hunk 的性质

- `bsd/kern/kern_exec.c`：删掉 `spawn_validate_persona` 里 `persona == NULL` 的提前返回
  （8796 的 `persona_lookup` 语义与 8020 不同，移植时**要看清 8020 的返回约定**再决定删不删）。
- `bsd/vm/vm_unix.c`、`osfmk/kern/kalloc.h`、`osfmk/kern/percpu.h`：上下文漂移，`patch -F3` 之后
  剩下的几行要人工对齐。
- `config/MASTER.arm64.bcm2837`（两处）、`makedefs/MakeInc.cmd`、`osfmk/conf/files.arm64`：
  构建配置/文件清单，8020 的写法不同，照 8020 的同类条目改。
