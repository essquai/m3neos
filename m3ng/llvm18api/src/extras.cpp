
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/DebugInfoMetadata.h"
/*
#include "llvm-c/DebugInfo.h"
#include "llvm/ADT/DenseMap.h" 
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
*/
#include "llvm/IR/DIBuilder.h"
/*
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/DebugLoc.h"
#include "llvm/IR/DebugProgramInstruction.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GVMaterializer.h"
#include "llvm/IR/Instruction.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Support/Casting.h"
*/

using namespace llvm;

template <typename DIT> DIT *unwrapDI(LLVMMetadataRef Ref) {
  return (DIT *)(Ref ? unwrap<MDNode>(Ref) : nullptr);
}

#ifdef __cplusplus
extern "C" {
#endif

//build a value ref of an 128 bit quad type from 2 64 bit values
//this function is for future reference if we ever get 128 bit float support
//in the front end and it should be in core.cpp.
LLVMValueRef LLVMConstQuad(LLVMContextRef C, const uint64_t qi[2]) {
  Type *ty = Type::getFP128Ty(*unwrap(C));
  //makearrayref deprecated
  //APInt ai(128,makeArrayRef(qi,2));
  APInt ai(128,ArrayRef<uint64_t>(qi,2));
  APFloat quad(APFloat::IEEEquad(), ai);
  return wrap(ConstantFP::get(ty,quad));  
}

//Get the function type for instrinsic functions. Should be in core.cpp
LLVMTypeRef LLVMGetFunctionType(LLVMValueRef Fn) {
  Function *Func = unwrap<Function>(Fn);
  FunctionType *FnT =
      cast<FunctionType>(Func->getFunctionType());
  return wrap(FnT);
}

LLVMMetadataRef LLVMDIBuilderCreateSetType(
    LLVMDIBuilderRef Builder, LLVMMetadataRef Scope, const char *Name,
    size_t NameLen, LLVMMetadataRef File, unsigned LineNumber,
    uint64_t SizeInBits, uint32_t AlignInBits, LLVMMetadataRef BaseTy) {
  return wrap(unwrap(Builder)->createSetType(
      unwrapDI<DIScope>(Scope), {Name, NameLen}, unwrapDI<DIFile>(File),
      LineNumber, SizeInBits, AlignInBits, unwrapDI<DIType>(BaseTy)));
}

void LLVMReplaceArrays(LLVMDIBuilderRef Builder, LLVMMetadataRef *T,
                       LLVMMetadataRef *Elements, unsigned NumElements) {
  auto CT = unwrap<DICompositeType>(*T);
  auto Elts =
      unwrap(Builder)->getOrCreateArray({unwrap(Elements), NumElements});
  unwrap(Builder)->replaceArrays(CT, Elts);
}

#ifdef __cplusplus
}
#endif

