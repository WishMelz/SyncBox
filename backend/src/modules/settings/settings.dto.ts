import { IsBoolean, IsInt, IsOptional, IsString, Length, Min, Max, Equals } from 'class-validator';
export class CleanupDto {
  @IsBoolean() enabled!: boolean;
  @IsInt() @Min(1) @Max(3650) idleDays!: number;
}
export class SecurityDto {
  @IsString() @Length(6, 128) password!: string;
  @IsOptional() @IsString() @Length(6, 40) code?: string;
}
export class ResetDto extends SecurityDto {
  @Equals('删除所有数据') confirmation!: string;
}
