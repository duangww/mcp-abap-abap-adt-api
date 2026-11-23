# MIR7/MIR4 删除预制发票时 `RBKP-ZZFPH01` 被清空 — 分析结论

- 日期：2026-08-06
- 事务：MIR7 / MIR4（删除预制发票）
- 增字段：`ZZFPH01`（发票号类，DE `ZEINVOICENUMBER` CHAR20）
- 屏幕增强函数组：`SAPLZFG_MM_04`
- BADI 实施：`ZBADI_FDCB_SUBBAS04` → `ZCL_IM_BADI_FDCB_SUBBAS04`

---

## 1. 现象

| 场景 | 结果 |
|------|------|
| 修改并保存 | `ZZFPH01` 可正常写入 `RBKP` |
| 打开单据后删除 | 删除流程中 `RBKPV-ZZFPH01` 已为空，库中原值可能被空值回写覆盖 |

Debug 关键：

1. `SAPLMR1M` / `LMR1MF02` / `FORM DELETE`：进入时 `RBKPV-ZZFPH01` 已空  
2. 真正清值点：`SAPLMR1M` / `LMR1MF4A` / `FORM MOVE_DATA_FROM_FI`（约 186 行）

```abap
MOVE-CORRESPONDING s_ac_vendor_comp_export TO p_rbkpv.
```

| 变量 | 执行前 |
|------|--------|
| `P_RBKPV-ZZFPH01` | 有值（如 `26507000000069781646`） |
| `S_AC_VENDOR_COMP_EXPORT-ZZFPH01` | 空 |

同名字段 `MOVE-CORRESPONDING` 后，`RBKPV` 侧被空值覆盖。  
调用栈多为 **MIR4 / PBO / 屏 6000→6005**，说明开单同步 FI→MM 时已丢，不是 `FORM DELETE` 本身清的。

---

## 2. 结论摘要

1. **不是**「删除专用标准 bug」、也**没有**专门 Note 说删除会错误丢掉 `ZZ*` 字段。  
2. **不是** `ZCL_IM_BADI_FDCB_SUBBAS04` 的 put/get 写错（类只是标准薄封装，修改保存正常说明屏幕链路可用）。  
3. **是** FI 对话框组件 export → `MOVE_DATA_FROM_FI` 回写时，`e_ac_vendor_comp_export-ZZFPH01` 为空，把已加载的 `RBKPV-ZZFPH01` 盖掉。  
4. DDIC 已基本齐全（见下），问题在 **`BADI_FDCB_SUBBAS04` 在 `COMP_EXPORT` 路径不重新 `get_data`**，导致 ZZ 进不了 export 结构。  
5. **不必再实现** `SUBBAS05/06/…` 才能写字段；一个 `SUBBAS04` 槽位足够，缺的是标准对 04 的 export 刷新。

---

## 3. 相关 Note / KBA（均不对症）

| Note/KBA | 内容 | 与本问题 |
|----------|------|----------|
| [3345659](https://userapps.support.sap.com/sap/support/knowledge/en/3345659) | MIR4/MIR7 删除预制发票过账逻辑 | 不谈客户字段 |
| [2579755](https://userapps.support.sap.com/sap/support/knowledge/en/2579755) | 预制发票批量删除 | 无关 |
| [2394017](https://userapps.support.sap.com/sap/support/knowledge/en/2394017) | 改预制发票抬头被重置；关键词含 `MOVE_DATA_FROM_FI` / `BADI_FDCB_SUBBASxx` / `RBKPV` | 症状族接近，**不会**自动保住 `ZZFPH01` |

公开渠道未找到「MIR7 删除导致 RBKP 客户字段丢失」的专用修复 Note。

---

## 4. 数据链路（问题路径）

```text
打开预制发票 / PBO
  → RBKPV 已带 ZZFPH01（从 RBKP 读入）
  → FI 组件 MM_VENDOR_DIALOG_COMP_EXPORT
       1) MOVE-CORRESPONDING BSEG/BSEC/BKPF → e_ac_vendor_comp_export  （无 ZZ）
       2) DO badi_max_number
            → badi_dyn_move_subscreen_to_mm( e_ac_vendor_comp_export )
              （本应把 INVFO/BADI 屏字段写入 export）
       → 结果：e_ac_vendor_comp_export-ZZFPH01 仍为空
  → LMR1MF4A MOVE_DATA_FROM_FI
       MOVE-CORRESPONDING s_ac_vendor_comp_export TO p_rbkpv
       → RBKPV-ZZFPH01 被清空
  → 用户删除：FORM DELETE → document_park( rbkpv )
       → 可能用空 ZZ 回写 RBKP
```

修改保存能写入：会走自定义屏 **PAI** → `get_data_from_screen_object` → `INVFO` 有值 → 写入 `RBKP`，与上述「未 PAI 就 export」路径不同。

---

## 5. 标准程序关键逻辑（`LFDCBFB0`）

### 5.1 `MM_VENDOR_DIALOG_COMP_EXPORT`（可疑 DO 循环）

```abap
DO badi_max_number TIMES.
  READ TABLE badi WITH KEY number = sy-index.
*(del) IF sy-subrc EQ 0 AND badi-invfo_after NE badi-invfo_before.
  IF sy-subrc EQ 0.                    " Note 723989：不再要求 after≠before
    PERFORM badi_dyn_move_subscreen_to_mm
                USING e_ac_vendor_comp_export.
  ENDIF.
ENDDO.
```

Note 723989 之后：只要 `badi` 表有条目就会进 FORM。  
可疑点不在外层 IF，而在 **FORM 内部是否刷新并写出 ZZ**。

### 5.2 `FORM badi_dyn_move_subscreen_to_mm`

写出 `V_FIELDS-<fld>`（即 `e_ac_vendor_comp_export`）的条件：

1. `badi-fields` 含屏字段（如 `INVFO-ZZFPH01`）  
2. `badi-invfo_after` / `before` 对应分量满足非空判断后赋值  
3. `ASSIGN V_FIELDS-ZZFPH01` 成功（export 结构有该字段）

**SUBBAS06～010：** export 前会 `CALL BADI …->get_data_from_screen_object`，刷新 `badi-invfo_after`。  
**SUBBAS04（本项目）：** 此 FORM **不调用** `get_data`，直接用内存里旧的 `badi-invfo_after`。

`SUBBAS04` 的 `get_data` 主要在 `badi_dyn_pai` 中调用。  
开单/PBO 走 `COMP_EXPORT` 且尚未 PAI 时，`badi-invfo_after-ZZFPH01` 常为空 → 不写或写出空 → 后续 `MOVE-CORRESPONDING` 清空 `RBKPV`。

### 5.3 是否还要再实现别的 BADI？

**不需要。**  
`e_ac_vendor_comp_export-ZZFPH01` 只依赖当前已激活的 `BADI_FDCB_SUBBAS0x` 槽位 + 其屏字段列表 + `invfo_after`。  
再挂 SUBBAS05/06… 不会自动修好 04 这条「export 不 get_data」的路径（除非整屏迁到会在 export 时 get_data 的槽位，改动大、一般不划算）。

---

## 6. DDIC 现状（DEV 查询 `DD03L`，字段 `ZZFPH01`）

已存在于（节选）：

- `RBKP`、`RBKP_V`
- `INVFO`
- `ACMM_VENDOR_COMP`
- `MRM_S_RBKPV` 等

Append 结构示例：`ZSMM_MIRO` / `ZSMM_MIRO_COMP` / `ZSMM_MIRO_INVFO` / `ZSMM_MIRO_V`。

→ **不是缺 `RBKP_V` / `ACMM_VENDOR_COMP` append**；问题在运行时 export 未带上值。

---

## 7. BADI 实施类（现状）

```abap
METHOD if_ex_badi_fdcb_subbas04~get_data_from_screen_object.
  ex_invfo = me->if_ex_badi_fdcb_subbas04~invfo.
ENDMETHOD.

METHOD if_ex_badi_fdcb_subbas04~put_data_to_screen_object.
  me->if_ex_badi_fdcb_subbas04~invfo = im_invfo.
ENDMETHOD.
```

符合官方薄封装用法；修改场景正常不能说明删除/开单 PBO 的 FI↔MM 回写也正常。

---

## 8. 建议验证断点

在 `LFDCBFB0` → `badi_dyn_move_subscreen_to_mm`（`badi-number = 4`）：

| 检查项 | 期望 |
|--------|------|
| `badi-fields` | 含 `…ZZFPH01` |
| `badi-invfo_after-ZZFPH01` | 开单 export 时是否已有值 |
| `badi-invfo_before-ZZFPH01` | 同上 |
| `ASSIGN ('V_FIELDS-ZZFPH01')` | `sy-subrc = 0` |

预期：after/before 皆空 → LOOP 不赋值 → export 保持空。

另在 `MOVE_DATA_FROM_FI` 确认覆盖前后 `P_RBKPV` / `S_AC_VENDOR_COMP_EXPORT`。

---

## 9. 修复方向（未实施，仅结论）

| 优先级 | 做法 | 说明 |
|--------|------|------|
| 推荐 | `MOVE_DATA_FROM_FI` 中 `MOVE-CORRESPONDING` 前后隐式增强：保护/写回 `p_rbkpv-zzfph01` | 改动小、对症、不依赖 PAI |
| 可选 | 保证 export 前 `badi-invfo_after` 已有 ZZ | 标准对 04 不调 get，难保证 |
| 不推荐作首选 | 整屏迁到 SUBBAS06+ | 利用其 export 时 get_data，成本高 |
| 无效 | 仅再实现一个空的 SUBBAS0x | 解决不了 04 的 export 缺口 |

业务注意：静默保护只避免被清空；若 FI 侧从未持有 ZZ，本质仍是「以 MM/RBKPV 为准保留」。

---

## 10. 一句话结论

**开单 PBO 经 `MM_VENDOR_DIALOG_COMP_EXPORT` → `badi_dyn_move_subscreen_to_mm` 时，`BADI_FDCB_SUBBAS04` 不重新 `get_data`，`ZZFPH01` 进不了 `e_ac_vendor_comp_export`，再被 `MOVE_DATA_FROM_FI` 的 `MOVE-CORRESPONDING` 清空 `RBKPV`；删除只是用了已被清空的内存抬头。非专用删除 Note 问题，也非必须再挂其它 BADI。**
