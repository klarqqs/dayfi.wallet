-- CreateEnum
CREATE TYPE "FwPaymentType" AS ENUM ('deposit', 'withdrawal');

-- CreateEnum
CREATE TYPE "FwPaymentStatus" AS ENUM ('initiated', 'pending', 'successful', 'failed');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "TransactionType" ADD VALUE 'fiatDeposit';
ALTER TYPE "TransactionType" ADD VALUE 'fiatWithdrawal';

-- AlterTable
ALTER TABLE "Transaction" ADD COLUMN     "fiatAmount" DOUBLE PRECISION,
ADD COLUMN     "fiatCurrency" TEXT,
ADD COLUMN     "flutterwaveRef" TEXT,
ADD COLUMN     "flutterwaveStatus" TEXT,
ADD COLUMN     "swapId" TEXT;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "fullName" TEXT,
ADD COLUMN     "virtualAccountBank" TEXT,
ADD COLUMN     "virtualAccountName" TEXT,
ADD COLUMN     "virtualAccountNumber" TEXT;

-- CreateTable
CREATE TABLE "FlutterwavePayment" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "txRef" TEXT NOT NULL,
    "flwRef" TEXT,
    "type" "FwPaymentType" NOT NULL,
    "fiatAmount" DOUBLE PRECISION NOT NULL,
    "onChainAmount" DOUBLE PRECISION,
    "currency" TEXT NOT NULL DEFAULT 'NGN',
    "status" "FwPaymentStatus" NOT NULL DEFAULT 'initiated',
    "providerStatus" TEXT,
    "providerMessage" TEXT,
    "retryCount" INTEGER NOT NULL DEFAULT 0,
    "lastRetriedAt" TIMESTAMP(3),
    "idempotencyKey" TEXT,
    "bankCode" TEXT,
    "accountNumber" TEXT,
    "accountName" TEXT,
    "customerEmail" TEXT,
    "customerName" TEXT,
    "redirectUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FlutterwavePayment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "FlutterwavePayment_txRef_key" ON "FlutterwavePayment"("txRef");

-- CreateIndex
CREATE INDEX "FlutterwavePayment_userId_idx" ON "FlutterwavePayment"("userId");

-- CreateIndex
CREATE INDEX "FlutterwavePayment_txRef_idx" ON "FlutterwavePayment"("txRef");

-- CreateIndex
CREATE INDEX "FlutterwavePayment_flwRef_idx" ON "FlutterwavePayment"("flwRef");

-- CreateIndex
CREATE INDEX "FlutterwavePayment_idempotencyKey_idx" ON "FlutterwavePayment"("idempotencyKey");

-- AddForeignKey
ALTER TABLE "FlutterwavePayment" ADD CONSTRAINT "FlutterwavePayment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
