<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feeders', function (Blueprint $table) {
            $table->increments('feeder_id');
            $table->unsignedInteger('depot_id');
            $table->string('feeder_code', 20);
            $table->string('feeder_name', 100)->nullable();
            $table->decimal('voltage_kv', 5, 2)->default(33.00);
            $table->enum('status', ['active', 'proposed', 'decommissioned'])->default('active');
            $table->timestamps();

            $table->foreign('depot_id')->references('depot_id')->on('depots')->onDelete('cascade');
            $table->unique(['depot_id', 'feeder_code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feeders');
    }
};
